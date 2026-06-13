import 'package:dio/dio.dart';
import 'package:xiangqi_solver/core/l10n/app_l10n.dart';

import '../constants/app_constants.dart';
import '../errors/exceptions.dart';
import '../utils/logger.dart';

/// Thin wrapper around [Dio] that centralizes base configuration and maps
/// transport-level failures to typed [AppException]s.
///
/// The base URL is configurable at runtime (Settings) so the same build can
/// point at an emulator host, a LAN device, or a remote server.
class DioClient {
  DioClient({Dio? dio, String? baseUrl, String? deviceId})
    : _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      baseUrl: baseUrl ?? AppConstants.defaultBackendUrl,
      connectTimeout: AppConstants.connectTimeout,
      receiveTimeout: AppConstants.receiveTimeout,
      sendTimeout: AppConstants.sendTimeout,
      // We validate status ourselves so we can read structured error envelopes.
      validateStatus: (_) => true,
      headers: {
        'Accept': 'application/json',
        // Stable per-install id so the backend can rate-limit per device
        // (cheap abuse cap now that hints are a device-local counter).
        'x-device-id': ?deviceId,
      },
    );
  }

  final Dio _dio;
  static const AppLogger _log = AppLogger('DioClient');

  /// The underlying client (exposed for advanced/streaming use).
  Dio get raw => _dio;

  /// Current base URL.
  String get baseUrl => _dio.options.baseUrl;

  /// Re-points the client at a new base URL (e.g. when settings change).
  set baseUrl(String value) {
    _dio.options = _dio.options.copyWith(baseUrl: value);
  }

  Future<Response<dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
    Duration? receiveTimeout,
  }) {
    return _guard(
      () => _dio.get<dynamic>(
        path,
        queryParameters: queryParameters,
        options: receiveTimeout == null
            ? null
            : Options(receiveTimeout: receiveTimeout),
      ),
    );
  }

  Future<Response<dynamic>> postJson(
    String path, {
    Object? data,
  }) {
    return _guard(
      () => _dio.post<dynamic>(
        path,
        data: data,
        options: Options(
          contentType: Headers.jsonContentType,
        ),
      ),
    );
  }

  Future<Response<dynamic>> postMultipart(
    String path, {
    required FormData formData,
    Map<String, String>? headers,
  }) {
    return _guard(
      () => _dio.post<dynamic>(
        path,
        data: formData,
        options: Options(contentType: 'multipart/form-data', headers: headers),
      ),
    );
  }

  /// Multipart POST whose response BODY is consumed as a byte stream (used for
  /// the progressive NDJSON analysis endpoint). The caller is responsible for
  /// draining `response.data.stream`. `receiveTimeout` applies BETWEEN chunks,
  /// so a live stream may outlast it in total.
  Future<Response<ResponseBody>> postMultipartStream(
    String path, {
    required FormData formData,
  }) {
    return _guard(
      () => _dio.post<ResponseBody>(
        path,
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          responseType: ResponseType.stream,
        ),
      ),
    );
  }

  /// Wraps a Dio call, translating [DioException]s into [NetworkException]s
  /// with friendly messages.
  Future<Response<T>> _guard<T>(
    Future<Response<T>> Function() run,
  ) async {
    try {
      return await run();
    } on DioException catch (e) {
      _log.warn('Dio error: ${e.type} ${e.message}');
      throw NetworkException(_describe(e), code: e.type.name);
    }
  }

  String _describe(DioException e) {
    return switch (e.type) {
      DioExceptionType.connectionTimeout =>
        AppL10n.current.netConnectTimeout(baseUrl),
      DioExceptionType.sendTimeout => AppL10n.current.netSendTimeout,
      DioExceptionType.receiveTimeout => AppL10n.current.netReceiveTimeout,
      DioExceptionType.connectionError =>
        AppL10n.current.netConnectError(baseUrl),
      DioExceptionType.badCertificate => AppL10n.current.netBadCert,
      DioExceptionType.cancel => AppL10n.current.netCancelled,
      DioExceptionType.badResponse => AppL10n.current.netBadResponse,
      DioExceptionType.unknown => e.message ?? AppL10n.current.netUnknown,
    };
  }
}
