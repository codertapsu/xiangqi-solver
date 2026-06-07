import '../../../core/constants/app_constants.dart';
import '../../../core/network/dio_client.dart';

/// Calls the backend install-grant endpoint to learn this device's STARTING hint
/// balance on (re)install. Keyed by the stable `x-device-id` header (set by
/// [DioClient]), so reinstalling on the same device doesn't re-grant the free
/// hints — unless the device is in the manual "Hint Grants" allowlist.
class HintGrantApi {
  HintGrantApi(this._client);

  final DioClient _client;

  /// POST /api/hints/claim → the starting hint balance for this install.
  /// Throws on a network/parse error; callers fall back to a local default.
  Future<int> claim() async {
    final resp = await _client.postJson(AppConstants.hintsClaimPath);
    final body = resp.data;
    if (body is Map && body['success'] == true && body['data'] is Map) {
      final hints = (body['data'] as Map)['hints'];
      if (hints is num) return hints.toInt();
    }
    throw const FormatException('Unexpected install-grant response.');
  }
}
