import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/remote_config/remote_config_provider.dart';
import '../../../core/utils/logger.dart';
import '../../solver/presentation/providers/solver_providers.dart'
    show dioClientProvider, sharedPreferencesProvider;
import '../data/billing_service.dart';
import '../data/hint_grant_api.dart';
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

/// Backend install-grant client (POST /api/hints/claim). Overridable in tests.
final hintGrantApiProvider = Provider<HintGrantApi>((ref) {
  return HintGrantApi(ref.watch(dioClientProvider));
});

/// The device-local hint balance. Hints live ONLY on this device (no server
/// wallet). The STARTING balance on (re)install is decided by the backend
/// (`POST /api/hints/claim`) so the free hints can't be farmed by reinstalling
/// (install ledger + manual "Hint Grants"); thereafter the balance is credited by
/// [add] (ad reward / purchase) and consumed by [spend] (one per cloud analysis).
/// Persisted to [SharedPreferences] on every change.
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
    // First ever launch on this install — the BACKEND decides the starting
    // balance (POST /api/hints/claim): it tracks installs so reinstalling doesn't
    // re-grant the free hints, and honors the manual "Hint Grants" allowlist.
    final granted = await _claimInstallGrant();
    if (!mounted) return;
    // Re-check in case a concurrent path seeded while we awaited.
    if (prefs.getBool(_kSeeded) ?? false) {
      state = prefs.getInt(_kBalance) ?? 0;
      return;
    }
    if (granted == null) {
      // The claim couldn't reach the backend. Do NOT bank free hints and do NOT
      // mark seeded — the next launch with a network re-claims. Seeding the free
      // count offline would let an airplane-mode reinstall farm hints (banked
      // offline, spent later online) and would never tell the server, so the
      // install ledger would never record the device. Showing the current balance
      // (0 on a fresh install) costs nothing: hints are only spendable on cloud
      // solves, which need the network anyway.
      state = prefs.getInt(_kBalance) ?? 0;
      return;
    }
    unawaited(prefs.setBool(_kSeeded, true));
    // Add the grant to whatever balance was credited WHILE we awaited the claim
    // (a purchase/ad reward can land mid-claim) rather than overwriting it.
    _set((prefs.getInt(_kBalance) ?? 0) + granted);
  }

  /// The starting hint balance from the backend, or `null` when the claim
  /// couldn't reach the backend (offline / timeout / error). A null result is NOT
  /// treated as a grant — see [_load] — so reinstalling offline can't bank the
  /// free hints. Capped so a slow/unreachable backend can't strand first run.
  Future<int?> _claimInstallGrant() async {
    try {
      return await _ref
          .read(hintGrantApiProvider)
          .claim()
          .timeout(const Duration(seconds: 6));
    } catch (e) {
      _log.info('Install-grant claim failed; will retry on the next launch: $e');
      return null;
    }
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
