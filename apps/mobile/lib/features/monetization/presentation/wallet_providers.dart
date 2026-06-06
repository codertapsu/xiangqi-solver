import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/remote_config/remote_config.dart';
import '../../../core/remote_config/remote_config_provider.dart';
import '../../../core/utils/logger.dart';
import '../../solver/presentation/providers/solver_providers.dart' show sharedPreferencesProvider;
import '../data/billing_service.dart';
import '../data/rewarded_ad_service.dart';
import '../domain/hint_pack.dart';
import '../monetization_config.dart';

const AppLogger _log = AppLogger('Wallet');

final rewardedAdServiceProvider = Provider<RewardedAdService>((ref) {
  final service = RewardedAdService(
    useRealAds: ref.watch(remoteConfigProvider).useRealAds,
  );
  ref.onDispose(service.dispose);
  return service;
});

final billingServiceProvider = Provider<BillingService>((ref) {
  final service = BillingService();
  ref.onDispose(service.dispose);
  return service;
});

/// The device-local hint balance. Hints live ONLY on this device (no server,
/// no account). Granted once on first install (the backend's `freeHintsOnInstall`
/// from remote config), credited by [add] (ad reward / purchase), and consumed by
/// [spend] (one per cloud analysis). Persisted to [SharedPreferences] on change.
class HintWalletNotifier extends StateNotifier<int> {
  HintWalletNotifier(this._ref) : super(0) {
    unawaited(_load());
    _attachBilling();
  }

  final Ref _ref;
  static const String _kBalance = 'hints.balance';
  static const String _kSeeded = 'hints.seeded';
  static const String _kOwnKeyCounter = 'hints.ownKeyCounter';

  SharedPreferences get _prefs => _ref.read(sharedPreferencesProvider);

  Future<void> _load() async {
    final prefs = _prefs;
    if (prefs.getBool(_kSeeded) ?? false) {
      state = prefs.getInt(_kBalance) ?? 0;
      return;
    }
    // First ever launch on this install — grant the free hints ONCE, using the
    // BACKEND-driven count (HINTS_FREE_ON_INSTALL). Wait for the first remote-
    // config fetch so the server value applies; fall back to the cached/default
    // (capping the wait so a slow/unreachable backend can't strand first run).
    RemoteConfig cfg;
    try {
      cfg = await _ref
          .read(remoteConfigProvider.notifier)
          .ensureLoaded()
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      cfg = _ref.read(remoteConfigProvider);
    }
    if (!mounted) return;
    // Re-check in case a concurrent path seeded while we awaited.
    if (prefs.getBool(_kSeeded) ?? false) {
      state = prefs.getInt(_kBalance) ?? 0;
      return;
    }
    unawaited(prefs.setBool(_kSeeded, true));
    _set(cfg.freeHintsOnInstall);
  }

  bool canSpend([int n = 1]) => state >= n;

  /// Credit hints (ad reward or a purchased pack). Persists immediately.
  void add(int n) {
    if (n <= 0) return;
    _set(state + n);
  }

  /// Consume hints for an analysis (clamped at zero). Persists immediately.
  void spend([int n = 1]) {
    if (n <= 0) return;
    _set(state - n < 0 ? 0 : state - n);
  }

  /// Charge a FRACTION of a hint for an own-key analysis: deduct one hint only
  /// after [divisor] such analyses (the user pays their own OpenAI cost; our
  /// cloud engine is the only cost we meter, at a discount). Counter persists.
  void spendForOwnKey(int divisor) {
    if (divisor <= 1) {
      spend();
      return;
    }
    final next = (_prefs.getInt(_kOwnKeyCounter) ?? 0) + 1;
    if (next >= divisor) {
      unawaited(_prefs.setInt(_kOwnKeyCounter, 0));
      spend();
    } else {
      unawaited(_prefs.setInt(_kOwnKeyCounter, next));
    }
  }

  void _set(int value) {
    state = value;
    unawaited(_prefs.setInt(_kBalance, value));
  }

  /// Wire the IAP purchase stream to local crediting: when Play reports a pack
  /// as `purchased`, add the corresponding hints. No server verification.
  void _attachBilling() {
    if (kUseMockMonetization) return; // mock buys credit directly from the sheet
    final billing = _ref.read(billingServiceProvider);
    billing.onPurchased = (productId) {
      final hints = hintsForProduct(productId);
      if (hints != null) {
        add(hints);
        _log.info('Credited $hints hints for $productId (local).');
      }
    };
    billing.onError = (message) => _log.warn('Billing: $message');
    // Fire-and-forget; swallow platform/availability errors (e.g. no Play / tests).
    unawaited(
      billing.init(kHintPacks.map((p) => p.productId)).catchError((Object _) => false),
    );
  }
}

final walletProvider = StateNotifierProvider<HintWalletNotifier, int>((ref) {
  return HintWalletNotifier(ref);
});
