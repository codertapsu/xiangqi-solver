import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/logger.dart';
import '../domain/analysis_result.dart';
import '../domain/board_piece.dart';
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
        'Screenshot file not found at ${screenshot.path}.',
        code: 'FILE_NOT_FOUND',
      );
    }
    final length = await screenshot.length();
    if (length > AppConstants.maxUploadBytes) {
      throw const FileException(
        'Image is larger than the 8 MB upload limit.',
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
      throw const ParseException(
        'Response envelope is missing a data object.',
        code: 'MISSING_DATA',
      );
    }
    try {
      return fromJson(data.cast<String, dynamic>());
    } catch (e) {
      _log.warn('Failed to parse response data: $e');
      throw const ParseException(
        'Could not understand the server response.',
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
        error['message']?.toString() ?? 'The server reported an error.',
        code: error['code']?.toString(),
        statusCode: statusCode,
        details: error['details'],
      );
    }
    return ServerException(
      'The server returned an error (HTTP ${statusCode ?? '?'}).',
      code: 'HTTP_$statusCode',
      statusCode: statusCode,
    );
  }

  void _ensureSuccessStatus(Response<dynamic> response) {
    final code = response.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw ServerException(
        'Health check failed (HTTP $code).',
        code: 'HTTP_$code',
        statusCode: code,
      );
    }
  }

  Map<String, dynamic> _asMap(dynamic data, {required String context}) {
    if (data is Map) return data.cast<String, dynamic>();
    throw ParseException(
      'Expected a JSON object for $context but got ${data.runtimeType}.',
      code: 'NOT_AN_OBJECT',
    );
  }

  String _fileName(String path) {
    final segments = path.split(Platform.pathSeparator);
    final name = segments.isEmpty ? 'screenshot.png' : segments.last;
    return name.isEmpty ? 'screenshot.png' : name;
  }
}
