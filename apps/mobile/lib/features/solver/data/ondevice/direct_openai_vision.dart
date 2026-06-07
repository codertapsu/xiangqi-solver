import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:xiangqi_solver/core/l10n/app_l10n.dart';

import '../../domain/board_piece.dart';
import '../../domain/solver_enums.dart';

/// The board state recognized by a vision provider (no engine analysis).
class BoardExtraction {
  const BoardExtraction({
    required this.boardDetected,
    required this.sideToMove,
    required this.confidence,
    required this.pieces,
    required this.warnings,
  });

  final bool boardDetected;
  final SideToMove sideToMove;
  final double confidence;
  final List<BoardPiece> pieces;
  final List<String> warnings;
}

/// Raised when on-device vision can't produce a board. [code] mirrors the
/// backend (e.g. `image_parse_error`, `VISION_API_ERROR`).
class OnDeviceVisionException implements Exception {
  const OnDeviceVisionException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'OnDeviceVisionException($code): $message';
}

/// Recognizes a Xiangqi board from an image. Seam so the analyzer can be unit
/// tested with a fake.
abstract interface class BoardVisionClient {
  Future<BoardExtraction> extract({
    required Uint8List imageBytes,
    required String mimeType,
    required String apiKey,
    SideToMove? sideToMoveHint,
    String? model,
  });
}

/// Calls the OpenAI multimodal API **directly** with the user's own key (the
/// On-device / BYO-key path). A port of the backend `openai.provider.ts`: same
/// strict board-extraction prompt, `detail:"high"` image, and JSON parsing —
/// but the key never leaves the device and the backend is bypassed.
class DirectOpenAiVisionClient implements BoardVisionClient {
  /// [model] is the fallback when `extract(model:)` isn't given. `gpt-4o-mini`
  /// is deliberately AVOIDED here — it misreads the small piece glyphs and
  /// yields illegal boards the engine rejects. The On-device settings let the
  /// user pick a model (and should match their Cloud backend's model).
  DirectOpenAiVisionClient({Dio? dio, this.model = 'gpt-5.4'}) : _dio = dio ?? Dio();

  final Dio _dio;
  final String model;

  static const String _url = 'https://api.openai.com/v1/chat/completions';

  @override
  Future<BoardExtraction> extract({
    required Uint8List imageBytes,
    required String mimeType,
    required String apiKey,
    SideToMove? sideToMoveHint,
    String? model,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw OnDeviceVisionException(
        AppL10n.current.visionMissingKey,
        code: 'MISSING_API_KEY',
      );
    }

    final dataUrl = 'data:$mimeType;base64,${base64Encode(imageBytes)}';
    final body = {
      'model': (model != null && model.trim().isNotEmpty) ? model.trim() : this.model,
      'temperature': 0,
      'response_format': {'type': 'json_object'},
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': _buildPrompt(sideToMoveHint)},
            {
              'type': 'image_url',
              'image_url': {'url': dataUrl, 'detail': 'high'},
            },
          ],
        },
      ],
    };

    Response<dynamic> res;
    try {
      res = await _dio.post<dynamic>(
        _url,
        data: body,
        options: Options(
          headers: {
            'Authorization': 'Bearer ${apiKey.trim()}',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (_) => true, // handle non-2xx ourselves
        ),
      );
    } on DioException catch (e) {
      throw OnDeviceVisionException(
        AppL10n.current.visionNetwork(e.message ?? e.type.name),
        code: 'NETWORK',
      );
    }

    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      final apiError = _parseApiError(res.data);
      final hint = apiError.code == 'image_parse_error'
          ? AppL10n.current.visionApiErrorImageHint
          : '';
      final base = AppL10n.current.visionApiError(status);
      final withDetail = apiError.message != null
          ? '${base.replaceFirst(RegExp(r'\.$'), '')}: ${apiError.message}'
          : base;
      throw OnDeviceVisionException(
        '$withDetail$hint',
        code: apiError.code ?? 'VISION_API_ERROR',
      );
    }

    final content = _content(res.data);
    if (content == null || content.trim().isEmpty) {
      throw OnDeviceVisionException(
        AppL10n.current.visionEmpty,
        code: 'VISION_EMPTY_RESPONSE',
      );
    }
    return _parse(content);
  }

  String _buildPrompt(SideToMove? hint) {
    const base = _boardExtractionPrompt;
    if (hint != null && hint != SideToMove.unknown) {
      return '$base\n\nHINT: The user indicated it is ${hint.wireValue}\'s turn to move.';
    }
    return base;
  }

  String? _content(dynamic data) {
    if (data is! Map) return null;
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final message = (choices.first as Map?)?['message'];
    return (message as Map?)?['content'] as String?;
  }

  ({String? message, String? code}) _parseApiError(dynamic data) {
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return (message: err['message'] as String?, code: err['code'] as String?);
    }
    return (message: null, code: null);
  }

  BoardExtraction _parse(String content) {
    final jsonText = _stripCodeFences(content);
    final Map<String, dynamic> obj;
    try {
      obj = jsonDecode(jsonText) as Map<String, dynamic>;
    } catch (_) {
      throw OnDeviceVisionException(
        AppL10n.current.visionBadJson,
        code: 'VISION_BAD_JSON',
      );
    }

    final warnings = (obj['warnings'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList();

    // 1) Parse raw pieces in whatever frame the model used (image row/col, or
    //    legacy canonical file/rank).
    final entries = <_RawPiece>[];
    var dropped = 0;
    for (final raw in (obj['pieces'] as List<dynamic>? ?? const [])) {
      if (raw is! Map) {
        dropped++;
        continue;
      }
      final m = raw.cast<String, dynamic>();
      final row = _asInt(m['row']);
      final col = _asInt(m['col']);
      final file = _asInt(m['file']);
      final rank = _asInt(m['rank']);
      final entry = _RawPiece(
        color: PieceColor.fromWire(m['color'] as String?),
        type: PieceType.fromWire(m['type'] as String?),
        row: row,
        col: col,
        file: file,
        rank: rank,
        confidence: (m['confidence'] as num?)?.toDouble(),
      );
      if (entry.hasPosition) {
        entries.add(entry);
      } else {
        dropped++;
      }
    }

    // 2) Decide orientation deterministically: the kings are a hard invariant,
    //    so derive from them; else the model's flag; else standard (Red-bottom).
    final redHomeAtTop = _resolveRedHomeAtTop(entries, obj['redHomeAtTop']);

    // 3) Rotate to canonical coords + bounds-check.
    final pieces = <BoardPiece>[];
    for (final e in entries) {
      final pos = e.toCanonical(redHomeAtTop);
      if (pos.file < 0 || pos.file > 8 || pos.rank < 0 || pos.rank > 9) {
        dropped++;
        continue;
      }
      pieces.add(BoardPiece(
        color: e.color,
        type: e.type,
        position: pos,
        confidence: e.confidence,
      ));
    }
    if (dropped > 0) {
      warnings.add(AppL10n.current.visionDroppedPieces(dropped));
    }

    return BoardExtraction(
      boardDetected: obj['boardDetected'] == true,
      sideToMove: SideToMove.fromWire(obj['sideToMove'] as String?),
      confidence: (obj['confidence'] as num?)?.toDouble() ?? 0,
      pieces: pieces,
      warnings: warnings,
    );
  }

  /// Red is at the top when the red general sits above the black general in the
  /// image (the hard invariant); fall back to the model's flag, else standard.
  bool _resolveRedHomeAtTop(List<_RawPiece> entries, Object? flag) {
    _RawPiece? king(PieceColor color) {
      for (final e in entries) {
        if (e.row != null && e.col != null && e.color == color && e.type == PieceType.king) {
          return e;
        }
      }
      return null;
    }

    final red = king(PieceColor.red);
    final black = king(PieceColor.black);
    if (red != null && black != null) return red.row! < black.row!;
    if (flag is bool) return flag;
    return false;
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  String _stripCodeFences(String text) {
    var t = text.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '');
      if (t.endsWith('```')) t = t.substring(0, t.length - 3);
    }
    return t.trim();
  }
}

/// A raw vision piece in whatever frame the model used (image row/col, or
/// legacy canonical file/rank), before deterministic rotation to canonical.
class _RawPiece {
  _RawPiece({
    required this.color,
    required this.type,
    this.row,
    this.col,
    this.file,
    this.rank,
    this.confidence,
  });

  final PieceColor color;
  final PieceType type;
  final int? row;
  final int? col;
  final int? file;
  final int? rank;
  final double? confidence;

  bool get hasPosition =>
      (row != null && col != null) || (file != null && rank != null);

  /// Rotate the image-space (row/col) position to canonical engine coords.
  /// `redHomeAtTop` means Red is drawn at the top (Black's perspective), a 180°
  /// rotation from standard. Legacy file/rank pass through unchanged.
  BoardPosition toCanonical(bool redHomeAtTop) {
    if (row != null && col != null) {
      return redHomeAtTop
          ? BoardPosition(file: 8 - col!, rank: row!)
          : BoardPosition(file: col!, rank: 9 - row!);
    }
    return BoardPosition(file: file ?? -1, rank: rank ?? -1);
  }
}

/// Strict board-extraction prompt — kept IN LOCKSTEP with the backend
/// `prompts/board-extraction.prompt.ts`. The model first fills a `grid` field (a
/// complete 10x9 FEN-like scan) as a perception scaffold, then transcribes the
/// board by IMAGE position (row/col) + reports `redHomeAtTop`; code rotates to
/// canonical and ignores `grid` (the parser drops unknown keys).
const String _boardExtractionPrompt = '''
You are a meticulous Xiangqi (Chinese chess) board digitizer. Your ONLY job is to read the board in the image and report every piece and its position as STRICT JSON. Do NOT suggest a move, evaluate the position, or add any strategy, commentary, or analysis.

THE BOARD
- Xiangqi is played on a grid of 9 vertical lines (files) x 10 horizontal lines (ranks). Pieces sit ON the line INTERSECTIONS (not inside the cells). There are 90 intersections; each holds AT MOST one piece.
- Two 3x3 "palaces" (each marked with a diagonal cross) sit at the top-center and bottom-center. KINGS and ADVISORS never leave their own palace. ELEPHANTS never cross the central river — they stay on their own half. PAWNS only ever advance. Use these facts only to SANITY-CHECK a reading, never to invent a piece.

COORDINATES — report exactly what you SEE, by image position. Do NOT rotate, flip, or normalize:
- row: integer 0..9. row 0 = the TOP rank line in the image, row 9 = the BOTTOM rank line.
- col: integer 0..8. col 0 = the LEFT file line, col 8 = the RIGHT file line.

PIECE COLORS: "red" or "black", shown by the disc/ink color AND the character.
PIECE TYPES (lowercase) with Chinese characters:
  "king" 帥/將, "advisor" 仕/士, "elephant" 相/象, "horse" 傌/馬, "rook" 俥/車, "cannon" 炮/砲/包, "pawn" 兵/卒.
Per side AT MOST: 1 king, 2 advisors, 2 elephants, 2 horses, 2 rooks, 2 cannons, 5 pawns. BOTH kings are ALWAYS on the board — find each inside its palace, even if partly covered by a move marker, highlight, last-move dot, or cursor.

HOW TO READ — fill the JSON fields IN ORDER:
1) "grid": transcribe ALL 10 rows, TOP (row 0) to BOTTOM (row 9). Each entry is a string of EXACTLY 9 chars, col 0 (left) to col 8 (right):
     "." = empty;  RED = UPPERCASE, BLACK = lowercase, using K=king A=advisor E=elephant H=horse R=rook C=cannon P=pawn.
   Example row: "rheakaehr". Read cell by cell — this grid IS your complete scan.
2) "redHomeAtTop": after scanning, true if the RED army (incl. red king 帥) is in the TOP half (rows 0..4), false if Red is at the bottom. A Black player's screenshot shows Red at the top -> true. Decide from where the red king actually sits.
3) "pieces": list EVERY non-empty intersection from your grid, with its color, type, and the SAME row/col. The pieces array MUST match the grid exactly.
4) Self-check: each side has exactly one king inside a palace; no side exceeds the maximums; no two pieces share a (row,col); pieces match grid. If anything is off, re-read that area; if still unsure, lower "confidence" and note it in "warnings".

OUTPUT a single JSON object with EXACTLY these fields:
{
  "boardDetected": boolean,
  "grid": ["row0", "row1", "row2", "row3", "row4", "row5", "row6", "row7", "row8", "row9"],
  "redHomeAtTop": boolean,
  "sideToMove": "red" | "black" | "unknown",
  "confidence": number,
  "pieces": [ { "color": "red", "type": "cannon", "row": 7, "col": 1, "confidence": 0.95 } ],
  "warnings": [ "string" ]
}

RULES:
- JSON only. No markdown, no code fences, no prose.
- Read each piece's CHARACTER to decide type and color; use palace/half/river only to sanity-check, never to guess from position alone.
- Every piece MUST have integer row 0..9 and col 0..8, matching where it sits in the IMAGE, and appear in "grid".
- Never place two pieces on the same (row, col). Do NOT invent pieces or exceed the per-side maximums.
- Do NOT output "file", "rank", "move", or any field not listed above.
- If you cannot read the board, set "boardDetected": false, "grid": [], "pieces": [], and explain in "warnings".''';
