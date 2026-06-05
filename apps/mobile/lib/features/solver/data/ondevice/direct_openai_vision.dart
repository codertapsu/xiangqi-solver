import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

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
  DirectOpenAiVisionClient({Dio? dio, this.model = 'gpt-4o'}) : _dio = dio ?? Dio();

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
      throw const OnDeviceVisionException(
        'No OpenAI API key configured. Add yours in Settings.',
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
        'Could not reach OpenAI: ${e.message ?? e.type.name}.',
        code: 'NETWORK',
      );
    }

    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      final apiError = _parseApiError(res.data);
      final hint = apiError.code == 'image_parse_error'
          ? ' The screenshot may be too small, corrupted, or not a real image.'
          : '';
      throw OnDeviceVisionException(
        'OpenAI request failed (HTTP $status)'
        '${apiError.message != null ? ': ${apiError.message}' : '.'}$hint',
        code: apiError.code ?? 'VISION_API_ERROR',
      );
    }

    final content = _content(res.data);
    if (content == null || content.trim().isEmpty) {
      throw const OnDeviceVisionException(
        'OpenAI returned an empty response.',
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
      throw const OnDeviceVisionException(
        'Could not understand the model response (invalid JSON).',
        code: 'VISION_BAD_JSON',
      );
    }

    final warnings = (obj['warnings'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList();

    final rawPieces = (obj['pieces'] as List<dynamic>? ?? const []);
    final pieces = <BoardPiece>[];
    var dropped = 0;
    for (final raw in rawPieces) {
      if (raw is! Map) {
        dropped++;
        continue;
      }
      try {
        final piece = BoardPiece.fromJson(raw.cast<String, dynamic>());
        if (piece.file < 0 || piece.file > 8 || piece.rank < 0 || piece.rank > 9) {
          dropped++;
          continue;
        }
        pieces.add(piece);
      } catch (_) {
        dropped++;
      }
    }
    if (dropped > 0) {
      warnings.add('Ignored $dropped malformed piece(s) from the vision response.');
    }

    return BoardExtraction(
      boardDetected: obj['boardDetected'] == true,
      sideToMove: SideToMove.fromWire(obj['sideToMove'] as String?),
      confidence: (obj['confidence'] as num?)?.toDouble() ?? 0,
      pieces: pieces,
      warnings: warnings,
    );
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

/// Strict board-extraction prompt — kept in sync with the backend
/// `prompts/board-extraction.prompt.ts`.
const String _boardExtractionPrompt = '''
You are a precise Xiangqi (Chinese chess) board digitizer.

Look at the provided image of a Xiangqi board and output ONLY the current board state as STRICT JSON. Do NOT suggest a move. Do NOT evaluate. Report only what pieces you see and where.

COORDINATE SYSTEM (use exactly this):
- file: integer 0..8. 0 = Red's far-left file, 8 = Red's far-right file.
- rank: integer 0..9. 0 = Red's home rank, 9 = Black's home rank (top).

PIECE COLORS: "red" or "black" (by ink color AND character).
PIECE TYPES (lowercase) with Chinese characters:
  "king" 帥/將, "advisor" 仕/士, "elephant" 相/象, "horse" 傌/馬, "rook" 俥/車, "cannon" 炮/砲/包, "pawn" 兵/卒.

Pieces sit on LINE INTERSECTIONS; each intersection holds AT MOST ONE piece.
Per side at most: 1 king, 2 advisors, 2 elephants, 2 horses, 2 rooks, 2 cannons, 5 pawns.
BOTH generals (kings) are ALWAYS on the board — find each inside its 3x3 palace.

OUTPUT a single JSON object with EXACTLY these fields:
{
  "boardDetected": boolean,
  "sideToMove": "red" | "black" | "unknown",
  "confidence": number,
  "pieces": [ { "color": "red", "type": "cannon", "file": 1, "rank": 2, "confidence": 0.95 } ],
  "warnings": [ "string" ]
}

RULES:
- JSON only. No markdown, no code fences, no prose.
- Every piece MUST have integer file 0..8 and rank 0..9.
- Never place two pieces on the same (file, rank). Do NOT invent pieces or exceed the per-side maximums.
- Read each piece's character to decide type and color.
- If you cannot read the board, set "boardDetected": false, "pieces": [], and explain in "warnings".''';
