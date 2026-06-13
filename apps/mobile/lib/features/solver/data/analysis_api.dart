import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:xiangqi_solver/core/l10n/app_l10n.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/logger.dart';
import '../domain/analysis_result.dart';
import '../domain/board_piece.dart';
import '../domain/board_state.dart';
import '../domain/solver_enums.dart';

/// Result of a health check, with measured round-trip latency.
class HealthStatus {
  const HealthStatus({
    required this.status,
    required this.timestamp,
    required this.uptimeSeconds,
    required this.version,
    required this.latency,
  });

  final String status;
  final String timestamp;
  final num uptimeSeconds;
  final String version;
  final Duration latency;

  bool get isOk => status == 'ok';
}

/// Tunable engine parameters shared by both analysis endpoints.
class EngineOptions {
  const EngineOptions({
    this.engineProvider,
    this.engineDepth,
    this.engineMoveTimeMs,
    this.engineMultiPv,
    this.engineThreads,
    this.engineHashMb,
  });

  final EngineProvider? engineProvider;
  final int? engineDepth;
  final int? engineMoveTimeMs;
  final int? engineMultiPv;
  final int? engineThreads;
  final int? engineHashMb;

  Map<String, dynamic> toJsonFields() => {
    if (engineProvider != null) 'engineProvider': engineProvider!.wireValue,
    if (engineDepth != null) 'engineDepth': engineDepth,
    if (engineMoveTimeMs != null) 'engineMoveTimeMs': engineMoveTimeMs,
    if (engineMultiPv != null) 'engineMultiPv': engineMultiPv,
    if (engineThreads != null) 'engineThreads': engineThreads,
    if (engineHashMb != null) 'engineHashMb': engineHashMb,
  };
}

/// Typed access to the analysis backend.
///
/// Speaks the shared envelope contract: success responses are
/// `{ success: true, data: <payload> }`, errors are
/// `{ success: false, error: { code, message, details? } }`. `/api/health` is
/// the one endpoint that is NOT wrapped.
class AnalysisApi {
  AnalysisApi(this._client);

  final DioClient _client;
  static const AppLogger _log = AppLogger('AnalysisApi');

  /// GET /api/health — returns the unwrapped status plus measured latency.
  Future<HealthStatus> health() async {
    final stopwatch = Stopwatch()..start();
    final response = await _client.getJson(
      AppConstants.healthPath,
      receiveTimeout: const Duration(seconds: 8),
    );
    stopwatch.stop();
    _ensureSuccessStatus(response);
    final body = _asMap(response.data, context: 'health');
    return HealthStatus(
      status: body['status'] as String? ?? 'unknown',
      timestamp: body['timestamp'] as String? ?? '',
      uptimeSeconds: (body['uptimeSeconds'] as num?) ?? 0,
      version: body['version'] as String? ?? 'unknown',
      latency: stopwatch.elapsed,
    );
  }

  /// POST /api/analysis/board — runs the engine directly on supplied pieces.
  Future<AnalysisResult> analyzeBoard({
    required SideToMove sideToMove,
    required List<BoardPiece> pieces,
    AiProvider? provider,
    String? language,
    EngineOptions options = const EngineOptions(),
  }) async {
    final payload = <String, dynamic>{
      if (provider != null) 'provider': provider.wireValue,
      'sideToMove': sideToMove.wireValue,
      'pieces': pieces.map((p) => p.toJson()).toList(growable: false),
      'language': ?language,
      ...options.toJsonFields(),
    };
    final response = await _client.postJson(
      AppConstants.analyzeBoardPath,
      data: payload,
    );
    return _parseEnvelopeData(response, AnalysisResult.fromJson);
  }

  /// POST /api/analysis/screenshot — multipart upload of a board image.
  Future<AnalysisResult> analyzeScreenshot(
    File screenshot, {
    AiProvider? provider,
    SideToMove? sideToMove,
    String? language,
    EngineOptions options = const EngineOptions(),
  }) async {
    if (!await screenshot.exists()) {
      throw FileException(
        AppL10n.current.apiFileNotFound(screenshot.path),
        code: 'FILE_NOT_FOUND',
      );
    }
    final length = await screenshot.length();
    if (length > AppConstants.maxUploadBytes) {
      throw FileException(
        AppL10n.current.apiFileTooLarge,
        code: 'FILE_TOO_LARGE',
      );
    }

    final formData = FormData.fromMap({
      'screenshot': await MultipartFile.fromFile(
        screenshot.path,
        filename: _fileName(screenshot.path),
      ),
      if (provider != null) 'provider': provider.wireValue,
      if (sideToMove != null) 'sideToMove': sideToMove.wireValue,
      'language': ?language,
      ...options.toJsonFields().map((k, v) => MapEntry(k, '$v')),
    });

    final response = await _client.postMultipart(
      AppConstants.analyzeScreenshotPath,
      formData: formData,
    );
    return _parseEnvelopeData(response, AnalysisResult.fromJson);
  }

  /// POST /api/analysis/screenshot/stream — progressive (NDJSON) analysis.
  ///
  /// Emits [onBoard] as soon as the backend has recognized + repaired the
  /// board (the engine is still searching), then resolves with the complete
  /// [AnalysisResult]. Throws a [ServerException] with code
  /// `STREAM_UNAVAILABLE` when the backend predates the endpoint (404/405) so
  /// the caller can fall back to the fused [analyzeScreenshot].
  Future<AnalysisResult> analyzeScreenshotStreamed(
    File screenshot, {
    AiProvider? provider,
    SideToMove? sideToMove,
    String? language,
    EngineOptions options = const EngineOptions(),
    required void Function(BoardState board) onBoard,
  }) async {
    if (!await screenshot.exists()) {
      throw FileException(
        AppL10n.current.apiFileNotFound(screenshot.path),
        code: 'FILE_NOT_FOUND',
      );
    }
    final formData = FormData.fromMap({
      'screenshot': await MultipartFile.fromFile(
        screenshot.path,
        filename: _fileName(screenshot.path),
      ),
      if (provider != null) 'provider': provider.wireValue,
      if (sideToMove != null) 'sideToMove': sideToMove.wireValue,
      'language': ?language,
      ...options.toJsonFields().map((k, v) => MapEntry(k, '$v')),
    });

    final response = await _client.postMultipartStream(
      AppConstants.analyzeScreenshotStreamPath,
      formData: formData,
    );
    final status = response.statusCode ?? 0;
    final body = response.data;
    if (status == 404 || status == 405 || body == null) {
      throw ServerException(
        AppL10n.current.apiServerHttpError('$status'),
        code: 'STREAM_UNAVAILABLE',
        statusCode: status,
      );
    }
    final text = body.stream
        .map<List<int>>((chunk) => chunk)
        .transform(utf8.decoder);
    if (status < 200 || status >= 300) {
      // Pre-stream failure: the standard { success:false, error } envelope.
      final raw = await text.join();
      Map<String, dynamic> envelope;
      try {
        envelope = (jsonDecode(raw) as Map).cast<String, dynamic>();
      } catch (_) {
        throw ServerException(
          AppL10n.current.apiServerHttpError('$status'),
          code: 'HTTP_$status',
          statusCode: status,
        );
      }
      throw _errorFromEnvelope(envelope, status);
    }

    AnalysisResult? result;
    await for (final line in text.transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final Map<String, dynamic> event;
      try {
        event = (jsonDecode(line) as Map).cast<String, dynamic>();
      } catch (_) {
        continue; // tolerate a corrupted line; later stages decide the outcome
      }
      switch (event['stage']) {
        case 'board':
          final board = event['board'];
          if (board is Map) {
            try {
              onBoard(BoardState.fromJson(board.cast<String, dynamic>()));
            } catch (e) {
              _log.warn('Ignoring unparseable board stage: $e');
            }
          }
        case 'done':
          final data = event['data'];
          if (data is Map) {
            result = AnalysisResult.fromJson(data.cast<String, dynamic>());
          }
        case 'error':
          final error = event['error'];
          throw ServerException(
            (error is Map ? error['message']?.toString() : null) ??
                AppL10n.current.apiServerError,
            code: error is Map ? error['code']?.toString() : null,
            statusCode: status,
          );
      }
    }
    if (result == null) {
      throw ParseException(
        AppL10n.current.apiMissingData,
        code: 'STREAM_INCOMPLETE',
      );
    }
    return result;
  }

  /// POST /api/analysis/extract — vision-only board recognition (no engine).
  ///
  /// Returns the recognized [BoardState] plus any vision/repair warnings; the
  /// caller computes the move itself (used by the "our key + on-device engine"
  /// mode, keeping the AI key server-side). The warnings are forwarded into the
  /// local engine step so board-quality feedback isn't lost on this path.
  Future<({BoardState board, List<String> warnings})> extractBoard(
    File screenshot, {
    AiProvider? provider,
    SideToMove? sideToMove,
  }) async {
    if (!await screenshot.exists()) {
      throw FileException(
        AppL10n.current.apiFileNotFound(screenshot.path),
        code: 'FILE_NOT_FOUND',
      );
    }
    final formData = FormData.fromMap({
      'screenshot': await MultipartFile.fromFile(
        screenshot.path,
        filename: _fileName(screenshot.path),
      ),
      if (provider != null) 'provider': provider.wireValue,
      if (sideToMove != null) 'sideToMove': sideToMove.wireValue,
    });
    final response = await _client.postMultipart(
      AppConstants.analyzeExtractPath,
      formData: formData,
    );
    return _parseEnvelopeData(
      response,
      (data) => (
        board: BoardState.fromJson((data['board'] as Map).cast<String, dynamic>()),
        warnings:
            (data['warnings'] as List?)?.map((w) => w.toString()).toList(growable: false) ??
            const <String>[],
      ),
    );
  }

  // --- envelope handling ---

  T _parseEnvelopeData<T>(
    Response<dynamic> response,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final body = _asMap(response.data, context: 'response');
    final success = body['success'] == true;
    if (!success || response.statusCode == null ||
        response.statusCode! >= 400) {
      throw _errorFromEnvelope(body, response.statusCode);
    }
    final data = body['data'];
    if (data is! Map) {
      throw ParseException(
        AppL10n.current.apiMissingData,
        code: 'MISSING_DATA',
      );
    }
    try {
      return fromJson(data.cast<String, dynamic>());
    } catch (e) {
      _log.warn('Failed to parse response data: $e');
      throw ParseException(
        AppL10n.current.apiParseError,
        code: 'PARSE_ERROR',
      );
    }
  }

  ServerException _errorFromEnvelope(
    Map<String, dynamic> body,
    int? statusCode,
  ) {
    final error = body['error'];
    if (error is Map) {
      return ServerException(
        error['message']?.toString() ?? AppL10n.current.apiServerError,
        code: error['code']?.toString(),
        statusCode: statusCode,
        details: error['details'],
      );
    }
    return ServerException(
      AppL10n.current.apiServerHttpError('${statusCode ?? '?'}'),
      code: 'HTTP_$statusCode',
      statusCode: statusCode,
    );
  }

  void _ensureSuccessStatus(Response<dynamic> response) {
    final code = response.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw ServerException(
        AppL10n.current.apiHealthFailed(code),
        code: 'HTTP_$code',
        statusCode: code,
      );
    }
  }

  Map<String, dynamic> _asMap(dynamic data, {required String context}) {
    if (data is Map) return data.cast<String, dynamic>();
    throw ParseException(
      AppL10n.current.apiParseContext(context, data.runtimeType.toString()),
      code: 'NOT_AN_OBJECT',
    );
  }

  String _fileName(String path) {
    final segments = path.split(Platform.pathSeparator);
    final name = segments.isEmpty ? 'screenshot.png' : segments.last;
    return name.isEmpty ? 'screenshot.png' : name;
  }
}
