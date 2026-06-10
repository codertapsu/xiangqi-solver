import 'package:dio/dio.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/security/secure_key_store.dart';

/// A failed admin request. [statusCode] 403 means the device isn't an admin or
/// the stored secret is missing/invalid (the UI should re-prompt for the secret).
class AdminException implements Exception {
  const AdminException({required this.message, required this.code, required this.statusCode});
  final String message;
  final String code;
  final int statusCode;

  bool get isForbidden => statusCode == 403;

  @override
  String toString() => 'AdminException($code/$statusCode): $message';
}

/// Client for the backend admin API (`/api/admin/*`).
///
/// Uses the shared Dio (which already sends the stable `x-device-id`) and adds
/// the `x-admin-secret` header (read from secure storage) to the guarded calls.
/// Reads the standard `{ success, data }` envelope; throws [AdminException] on
/// any non-2xx / error envelope so the UI can react (e.g. re-prompt on 403).
class AdminApi {
  AdminApi(this._dio, this._keys);

  final Dio _dio;
  final SecureKeyStore _keys;

  /// Whether THIS device is an admin (identity only — no secret needed).
  Future<bool> isAdmin() async {
    final res = await _dio.get<dynamic>(
      AppConstants.adminStatusPath,
      options: Options(validateStatus: (_) => true),
    );
    final body = res.data;
    if (res.statusCode == 200 && body is Map && body['success'] == true) {
      final data = body['data'];
      return data is Map && data['isAdmin'] == true;
    }
    return false;
  }

  // --- Remote config -------------------------------------------------------

  /// The effective remote config (a raw `features` map) + whether it's overridden.
  Future<({Map<String, dynamic> features, bool overridden})> getConfig() async {
    final data = await _send('GET', AppConstants.adminConfigPath) as Map;
    return (
      features: (data['features'] as Map).cast<String, dynamic>(),
      overridden: data['overridden'] == true,
    );
  }

  /// Replace the remote config with [features] (the full features map).
  Future<void> setConfig(Map<String, dynamic> features) =>
      _send('PUT', AppConstants.adminConfigPath, body: features);

  /// Reset the remote config to the server defaults (delete the override).
  Future<void> resetConfig() => _send('DELETE', AppConstants.adminConfigPath);

  // --- Hint grants ---------------------------------------------------------

  Future<Map<String, int>> getGrants() async {
    final data = await _send('GET', AppConstants.adminGrantsPath) as Map;
    return data.map((k, v) => MapEntry(k as String, (v as num).toInt()));
  }

  Future<void> setGrant(String deviceId, int hints) =>
      _send('PUT', AppConstants.adminGrantsPath, body: {'deviceId': deviceId, 'hints': hints});

  Future<void> removeGrant(String deviceId) =>
      _send('DELETE', AppConstants.adminGrantsPath, body: {'deviceId': deviceId});

  // --- Install ledger ------------------------------------------------------

  Future<Map<String, String>> getInstalls() async {
    final data = await _send('GET', AppConstants.adminInstallsPath) as Map;
    return data.map((k, v) => MapEntry(k as String, v as String));
  }

  Future<void> setInstall(String deviceId, {String? firstSeen}) => _send(
    'PUT',
    AppConstants.adminInstallsPath,
    body: {'deviceId': deviceId, 'firstSeen': ?firstSeen},
  );

  Future<void> removeInstall(String deviceId) =>
      _send('DELETE', AppConstants.adminInstallsPath, body: {'deviceId': deviceId});

  // --- internals -----------------------------------------------------------

  /// Sends a guarded request with the admin secret header and unwraps the
  /// envelope, throwing [AdminException] on failure. Returns the `data` payload.
  Future<dynamic> _send(String method, String path, {Object? body}) async {
    final secret = await _keys.readAdminSecret() ?? '';
    final res = await _dio.request<dynamic>(
      path,
      data: body,
      options: Options(
        method: method,
        headers: {'x-admin-secret': secret},
        contentType: Headers.jsonContentType,
        validateStatus: (_) => true,
      ),
    );
    final payload = res.data;
    if (res.statusCode == 200 && payload is Map && payload['success'] == true) {
      return payload['data'];
    }
    final err = (payload is Map && payload['error'] is Map) ? payload['error'] as Map : null;
    throw AdminException(
      message: err?['message']?.toString() ?? 'Request failed (HTTP ${res.statusCode}).',
      code: err?['code']?.toString() ?? 'HTTP_${res.statusCode}',
      statusCode: res.statusCode ?? 0,
    );
  }
}
