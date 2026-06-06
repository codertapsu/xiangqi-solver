import 'dart:io';
import 'dart:typed_data';

import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_result.dart';
import '../../../../core/security/secure_key_store.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/analysis_result.dart';
import '../../domain/best_move.dart';
import '../../domain/board_piece.dart';
import '../../domain/board_state.dart';
import '../../domain/solver_enums.dart';
import 'direct_openai_vision.dart';
import 'local/board_repair.dart';
import 'local/local_fen.dart';
import 'local/local_notation.dart';
import 'on_device_engine.dart';

/// A recognized board plus any vision/repair warnings, produced by the own-key
/// vision step. Kept separate from the engine step so the two halves can be
/// mixed with the cloud halves (the 2x2 AI-key x engine matrix).
typedef VisionResult = ({BoardState board, List<String> warnings});

/// On-device building blocks for analysis:
///  - [extractBoardOwnKey]: direct AI vision with the user's OWN key → board.
///  - [solveLocally]: the local Pikafish engine on a recognized board → result.
///  - [analyze]: the fully-local composition of both.
///
/// The two steps are composed differently per mode (e.g. our-key vision +
/// local engine, or own-key vision + cloud engine) by the AnalysisNotifier.
class OnDeviceAnalyzer {
  OnDeviceAnalyzer(this._keys, this._vision);

  final SecureKeyStore _keys;
  final BoardVisionClient _vision;
  static const AppLogger _log = AppLogger('OnDeviceAnalyzer');

  /// Vision via the user's OWN key (direct OpenAI), repaired into a board. The
  /// key never leaves the device and no backend is used.
  Future<ApiResult<VisionResult>> extractBoardOwnKey(
    File screenshot, {
    SideToMove? sideToMove,
    String visionModel = 'gpt-4o',
  }) async {
    final apiKey = await _keys.readOpenAiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      return const ApiResult<VisionResult>.failure(
        OnDeviceFailure(
          'Using your own key needs an OpenAI API key. Add it in Settings.',
          code: 'MISSING_API_KEY',
        ),
      );
    }

    final BoardExtraction extraction;
    try {
      final bytes = await screenshot.readAsBytes();
      extraction = await _vision.extract(
        imageBytes: bytes,
        mimeType: _sniffMime(bytes),
        apiKey: apiKey,
        sideToMoveHint: sideToMove,
        model: visionModel,
      );
    } on OnDeviceVisionException catch (e) {
      return ApiResult.failure(OnDeviceFailure(e.message, code: e.code ?? 'VISION_ERROR'));
    } catch (e) {
      _log.warn('On-device vision failed: $e');
      return ApiResult.failure(OnDeviceFailure('On-device vision failed: $e', code: 'VISION_ERROR'));
    }

    final repaired = repairBoard(extraction.pieces);
    final side = (sideToMove != null && sideToMove != SideToMove.unknown)
        ? sideToMove
        : extraction.sideToMove;
    final board = BoardState(
      sideToMove: side,
      fen: toFen(repaired.pieces, side),
      pieces: repaired.pieces,
      confidence: extraction.confidence,
    );
    return ApiResult.success((
      board: board,
      warnings: [...extraction.warnings, ...repaired.warnings],
    ));
  }

  /// Runs the LOCAL Pikafish engine on a recognized [board]. [visionStatus]
  /// records where the board came from (own key vs our backend). When the engine
  /// is unavailable/illegal, returns the board alone with a clear warning.
  Future<ApiResult<AnalysisResult>> solveLocally(
    BoardState board, {
    required OnDeviceEngine engine,
    required ProviderStatus visionStatus,
    String language = 'en',
    int depth = 12,
    int? threads,
    int? hashMb,
    int? multiPv,
    List<String> warnings = const [],
  }) async {
    final pieces = board.pieces;
    final allWarnings = [...warnings];

    if (!engine.isAvailable) {
      allWarnings.add(
        'The on-device engine is not ready, so the best move was not computed. '
        'Switch the engine to Cloud in Settings to finish.',
      );
      return _boardOnly(board, allWarnings, visionStatus, engineOk: false);
    }
    if (!hasBothGenerals(pieces)) {
      allWarnings.add(
        'Could not locate both generals, so the best move was not computed. '
        'Try re-capturing with a clearer view of the board.',
      );
      return _boardOnly(board, allWarnings, visionStatus, engineOk: false);
    }

    try {
      final move = await engine.bestMove(
        board,
        depth: depth,
        threads: threads,
        hashMb: hashMb,
        multiPv: multiPv,
      );
      final best = _toBestMove(move, pieces, language);
      final candidates =
          move.multipv.map((m) => _toBestMove(m, pieces, language)).toList(growable: false);
      return ApiResult.success(
        AnalysisResult(
          analysisId: '',
          board: board,
          bestMove: best,
          candidates: candidates,
          explanation:
              '${best.human} (${best.notation}) — eval ${best.score}, depth ${best.depth}.',
          warnings: allWarnings,
          engine: const ProviderStatus(provider: 'pikafish (on-device)', ok: true),
          vision: visionStatus,
        ),
      );
    } on OnDeviceEngineException catch (e) {
      _log.warn('On-device engine failed: ${e.message}');
      allWarnings.add(_isIllegalPosition(e.message)
          ? 'The recognized board isn\'t a legal Xiangqi position — some pieces '
                'were misread onto impossible squares, so no move was computed. '
                'Re-capture with a clearer view, or use a stronger Vision model.'
          : 'On-device engine failed: ${e.message}');
      return _boardOnly(board, allWarnings, visionStatus, engineOk: false);
    }
  }

  /// Fully-local: own-key vision + local engine (no backend).
  Future<ApiResult<AnalysisResult>> analyze(
    File screenshot, {
    required OnDeviceEngine engine,
    SideToMove? sideToMove,
    String language = 'en',
    String visionModel = 'gpt-4o',
    int depth = 12,
    int? threads,
    int? hashMb,
    int? multiPv,
  }) async {
    final visionRes = await extractBoardOwnKey(
      screenshot,
      sideToMove: sideToMove,
      visionModel: visionModel,
    );
    return visionRes.when(
      success: (v) => solveLocally(
        v.board,
        engine: engine,
        visionStatus: const ProviderStatus(provider: 'openai (your key)', ok: true),
        language: language,
        depth: depth,
        threads: threads,
        hashMb: hashMb,
        multiPv: multiPv,
        warnings: v.warnings,
      ),
      failure: (f) => Future.value(ApiResult<AnalysisResult>.failure(f)),
    );
  }

  /// Pikafish rejects boards with pieces on impossible squares — a vision
  /// misread, not an engine fault. Detect that so we can explain it usefully.
  bool _isIllegalPosition(String message) {
    final m = message.toLowerCase();
    return m.contains('unsupported position') ||
        m.contains('invalid position') ||
        m.contains('on invalid');
  }

  BestMove _toBestMove(LocalEngineMove m, List<BoardPiece> pieces, String language) {
    final d = describeMove(from: m.from, to: m.to, pieces: pieces, language: language);
    return BestMove(
      from: m.from,
      to: m.to,
      uci: m.uci,
      human: d.human,
      notation: d.wxf,
      score: m.score,
      depth: m.depth,
    );
  }

  ApiResult<AnalysisResult> _boardOnly(
    BoardState board,
    List<String> warnings,
    ProviderStatus visionStatus, {
    required bool engineOk,
  }) {
    return ApiResult.success(
      AnalysisResult(
        analysisId: '',
        board: board,
        bestMove: null,
        explanation: 'Board recognized. No move was computed.',
        warnings: warnings,
        engine: ProviderStatus(provider: 'pikafish (on-device)', ok: engineOk),
        vision: visionStatus,
      ),
    );
  }

  /// Detects the image type from magic bytes (so the data URL mime matches).
  String _sniffMime(Uint8List b) {
    if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47) {
      return 'image/png';
    }
    if (b.length >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) {
      return 'image/jpeg';
    }
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return 'image/webp';
    }
    return 'image/png';
  }
}
