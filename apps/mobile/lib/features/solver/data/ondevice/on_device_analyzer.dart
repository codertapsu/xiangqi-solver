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

/// Coordinates the experimental **On-device (Offline)** path entirely on the
/// device: direct AI vision (the user's OWN key) → repair → local engine →
/// localized result. The AI key never leaves the device and no backend is used.
///
/// When the bundled engine isn't available it still returns the recognized
/// board (no move) with a clear warning. See docs/ON_DEVICE_ENGINE.md.
class OnDeviceAnalyzer {
  OnDeviceAnalyzer(this._keys, this._vision);

  final SecureKeyStore _keys;
  final BoardVisionClient _vision;
  static const AppLogger _log = AppLogger('OnDeviceAnalyzer');

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
    final apiKey = await _keys.readOpenAiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      return _fail(
        'On-device mode needs your own OpenAI API key. Add it in Settings.',
        'MISSING_API_KEY',
      );
    }

    // 1. Vision via the user's key (BYO). Surfaces key/image errors directly.
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
      return _fail(e.message, e.code ?? 'VISION_ERROR');
    } catch (e) {
      _log.warn('On-device vision failed: $e');
      return _fail('On-device vision failed: $e', 'VISION_ERROR');
    }

    // 2. Repair the (imperfect) board and build it.
    final repaired = repairBoard(extraction.pieces);
    final warnings = [...extraction.warnings, ...repaired.warnings];
    final side = (sideToMove != null && sideToMove != SideToMove.unknown)
        ? sideToMove
        : extraction.sideToMove;
    final board = BoardState(
      sideToMove: side,
      fen: toFen(repaired.pieces, side),
      pieces: repaired.pieces,
      confidence: extraction.confidence,
    );

    // 3. Engine — or return the board alone when it isn't available.
    if (!engine.isAvailable) {
      warnings.add(
        'On-device engine is not available (binary/NNUE not installed), so the '
        'best move was not computed. Switch to Cloud mode in Settings to finish.',
      );
      return _boardOnly(board, warnings, language, ok: false, provider: 'on-device (pending)');
    }
    if (!hasBothGenerals(repaired.pieces)) {
      warnings.add(
        'Could not locate both generals, so the best move was not computed. '
        'Try re-capturing with a clearer view of the board.',
      );
      return _boardOnly(board, warnings, language, ok: false, provider: 'pikafish (on-device)');
    }

    try {
      final move = await engine.bestMove(
        board,
        depth: depth,
        threads: threads,
        hashMb: hashMb,
        multiPv: multiPv,
      );
      final best = _toBestMove(move, repaired.pieces, language);
      final candidates = move.multipv
          .map((m) => _toBestMove(m, repaired.pieces, language))
          .toList(growable: false);
      return ApiResult.success(
        AnalysisResult(
          analysisId: '',
          board: board,
          bestMove: best,
          candidates: candidates,
          explanation: '${best.human} (${best.notation}) — eval ${best.score}, depth ${best.depth}.',
          warnings: warnings,
          engine: const ProviderStatus(provider: 'pikafish (on-device)', ok: true),
          vision: const ProviderStatus(provider: 'openai (your key)', ok: true),
        ),
      );
    } on OnDeviceEngineException catch (e) {
      _log.warn('On-device engine failed: ${e.message}');
      warnings.add(_isIllegalPosition(e.message)
          ? 'The recognized board isn\'t a legal Xiangqi position — some pieces '
                'were misread onto impossible squares, so no move was computed. '
                'Re-capture with a clearer, larger view, or set a stronger '
                'Vision model in Settings (e.g. the model your Cloud mode uses).'
          : 'On-device engine failed: ${e.message}');
      return _boardOnly(board, warnings, language, ok: false, provider: 'pikafish (on-device)');
    }
  }

  /// Pikafish rejects boards with pieces on impossible squares (advisors/
  /// elephants off their points, kings out of the palace) — a vision misread,
  /// not an engine fault. Detect that so we can explain it usefully.
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
    String language, {
    required bool ok,
    required String provider,
  }) {
    return ApiResult.success(
      AnalysisResult(
        analysisId: '',
        board: board,
        bestMove: null,
        explanation:
            'Board recognized on this device with your OpenAI key. No move was computed.',
        warnings: warnings,
        engine: ProviderStatus(provider: provider, ok: ok),
        vision: const ProviderStatus(provider: 'openai (your key)', ok: true),
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

  ApiResult<AnalysisResult> _fail(String message, String code) {
    return ApiResult<AnalysisResult>.failure(OnDeviceFailure(message, code: code));
  }
}
