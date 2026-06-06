import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/solver/presentation/providers/solver_providers.dart'
    show dioClientProvider, sharedPreferencesProvider;
import '../constants/app_constants.dart';
import '../utils/logger.dart';
import 'remote_config.dart';

/// Holds the current [RemoteConfig]. Seeds from the on-disk cache (or
/// [RemoteConfig.defaults]) synchronously, then refreshes from `GET /api/config`
/// in the background and caches the result. Never throws — a failed fetch keeps
/// the cached/default value, so the app always renders.
class RemoteConfigNotifier extends StateNotifier<RemoteConfig> {
  RemoteConfigNotifier(this._ref) : super(_loadCached(_ref)) {
    _firstLoad = refresh();
  }

  final Ref _ref;
  static const AppLogger _log = AppLogger('RemoteConfig');
  static const String _kCache = 'remoteConfig.cache';

  /// Completes after the FIRST fetch ATTEMPT (success or failure). Used by
  /// callers that must apply a server value on first launch (see [ensureLoaded]).
  late final Future<void> _firstLoad;

  /// Resolves to the config once the first fetch attempt has completed, so a
  /// first-launch consumer (e.g. the initial free-hint grant) waits for the
  /// backend value instead of seeding a stale default. Never throws — a failed
  /// fetch resolves to the cached/default config.
  Future<RemoteConfig> ensureLoaded() async {
    await _firstLoad;
    return state;
  }

  static RemoteConfig _loadCached(Ref ref) {
    try {
      final raw = ref.read(sharedPreferencesProvider).getString(_kCache);
      if (raw != null && raw.isNotEmpty) {
        return RemoteConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // ignore — fall through to defaults
    }
    return RemoteConfig.defaults;
  }

  /// Fetch the latest config and cache it. Safe to call repeatedly.
  Future<void> refresh() async {
    try {
      final resp = await _ref.read(dioClientProvider).getJson(AppConstants.configPath);
      final body = resp.data;
      if (body is Map && body['success'] == true && body['data'] is Map) {
        final cfg = RemoteConfig.fromJson((body['data'] as Map).cast<String, dynamic>());
        if (!mounted) return;
        state = cfg;
        unawaited(
          _ref.read(sharedPreferencesProvider).setString(_kCache, jsonEncode(cfg.toJson())),
        );
      }
    } catch (e) {
      _log.info('Remote config fetch failed (using cached/defaults): $e');
    }
  }
}

final remoteConfigProvider = StateNotifierProvider<RemoteConfigNotifier, RemoteConfig>((ref) {
  return RemoteConfigNotifier(ref);
});
