import 'dart:io';

import '../../../core/errors/exceptions.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/api_result.dart';
import '../../../core/utils/logger.dart';
import '../domain/analysis_result.dart';
import '../domain/board_piece.dart';
import '../domain/board_state.dart';
import '../domain/solver_enums.dart';
import 'analysis_api.dart';

/// Application-facing gateway to analysis use cases.
///
/// Wraps [AnalysisApi], translating low-level [AppException]s into [Failure]s
/// and returning an [ApiResult] so the presentation layer handles errors
/// explicitly instead of catching exceptions.
class AnalysisRepository {
  AnalysisRepository(this._api);

  final AnalysisApi _api;
  static const AppLogger _log = AppLogger('AnalysisRepository');

  Future<ApiResult<HealthStatus>> checkHealth() {
    return _run(() => _api.health());
  }

  Future<ApiResult<AnalysisResult>> analyzeBoard({
    required SideToMove sideToMove,
    required List<BoardPiece> pieces,
    AiProvider? provider,
    String? language,
    EngineOptions options = const EngineOptions(),
  }) {
    return _run(
      () => _api.analyzeBoard(
        sideToMove: sideToMove,
        pieces: pieces,
        provider: provider,
        language: language,
        options: options,
      ),
    );
  }

  Future<ApiResult<AnalysisResult>> analyzeScreenshot(
    File screenshot, {
    AiProvider? provider,
    SideToMove? sideToMove,
    String? language,
    EngineOptions options = const EngineOptions(),
  }) {
    return _run(
      () => _api.analyzeScreenshot(
        screenshot,
        provider: provider,
        sideToMove: sideToMove,
        language: language,
        options: options,
      ),
    );
  }

  /// Progressive analysis: [onBoard] fires when the board is recognized (the
  /// engine is still searching); resolves with the full result. Fails with
  /// code `STREAM_UNAVAILABLE` when the backend lacks the streaming endpoint —
  /// callers fall back to [analyzeScreenshot].
  Future<ApiResult<AnalysisResult>> analyzeScreenshotStreamed(
    File screenshot, {
    AiProvider? provider,
    SideToMove? sideToMove,
    String? language,
    EngineOptions options = const EngineOptions(),
    required void Function(BoardState board) onBoard,
  }) {
    return _run(
      () => _api.analyzeScreenshotStreamed(
        screenshot,
        provider: provider,
        sideToMove: sideToMove,
        language: language,
        options: options,
        onBoard: onBoard,
      ),
    );
  }

  /// Vision-only board recognition (no engine) — board + vision warnings.
  Future<ApiResult<({BoardState board, List<String> warnings})>> extractBoard(
    File screenshot, {
    AiProvider? provider,
    SideToMove? sideToMove,
  }) {
    return _run(
      () => _api.extractBoard(
        screenshot,
        provider: provider,
        sideToMove: sideToMove,
      ),
    );
  }

  /// Executes [action], converting any thrown [AppException] (or unexpected
  /// error) into the appropriate [Failure].
  Future<ApiResult<T>> _run<T>(Future<T> Function() action) async {
    try {
      final value = await action();
      return ApiResult.success(value);
    } on NetworkException catch (e) {
      return ApiResult.failure(NetworkFailure(e.message, code: e.code));
    } on ServerException catch (e) {
      return ApiResult.failure(
        ServerFailure(e.message, code: e.code, statusCode: e.statusCode),
      );
    } on ParseException catch (e) {
      return ApiResult.failure(ParseFailure(e.message, code: e.code));
    } on FileException catch (e) {
      return ApiResult.failure(FileFailure(e.message, code: e.code));
    } on AppException catch (e) {
      return ApiResult.failure(UnknownFailure(e.message, code: e.code));
    } catch (e, st) {
      _log.error('Unexpected repository error', e, st);
      return ApiResult.failure(UnknownFailure('Unexpected error: $e'));
    }
  }
}
