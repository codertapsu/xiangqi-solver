import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/utils/logger.dart';
import 'ad_helper.dart';

/// Loads and shows a single rewarded ad at a time. When the user earns the
/// reward, [onEarned] fires and the caller credits a hint LOCALLY — there is no
/// AdMob Server-Side Verification (SSV).
class RewardedAdService {
  RewardedAdService({this.useRealAds = false});

  static const AppLogger _log = AppLogger('RewardedAd');

  /// Whether to load the REAL ad unit (vs Google's test unit) — from remote config.
  final bool useRealAds;

  RewardedAd? _ad;

  /// Completes when an in-flight load finishes (true = an ad is ready). Lets
  /// concurrent callers (preload + a tap) await the SAME load instead of
  /// starting duplicate requests.
  Completer<bool>? _inFlight;

  bool get isReady => _ad != null;

  /// Ensures an ad is loaded, returning true once one is ready (false if the
  /// load failed or ads aren't supported here). Idempotent: if a load is already
  /// running, the caller awaits that one. This is the key to one-tap behavior —
  /// [show] awaits it, so the first tap waits for the ad instead of failing.
  Future<bool> ensureLoaded() {
    if (!(Platform.isAndroid || Platform.isIOS)) return Future.value(false);
    if (_ad != null) return Future.value(true);
    final existing = _inFlight;
    if (existing != null) return existing.future;

    final completer = Completer<bool>();
    _inFlight = completer;
    RewardedAd.load(
      adUnitId: AdHelper.rewardedAdUnitId(useRealAds: useRealAds),
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _inFlight = null;
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (err) {
          _log.warn('Rewarded ad failed to load: ${err.code} ${err.message}');
          _ad = null;
          _inFlight = null;
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );
    return completer.future;
  }

  /// Preload an ad (fire-and-forget) so the next [show] is instant. Safe to call
  /// repeatedly. No-op off mobile (host/tests).
  void load() => unawaited(ensureLoaded());

  /// Shows a rewarded ad. If none is preloaded yet, this AWAITS a load first
  /// (so a single tap works — the caller shows a spinner during the wait).
  /// Returns false only if no ad could be loaded. [onEarned] fires when the
  /// reward is granted; [onClosed] fires after the ad is dismissed.
  Future<bool> show({VoidCallback? onEarned, VoidCallback? onClosed}) async {
    if (_ad == null) await ensureLoaded();
    final ad = _ad;
    if (ad == null) return false;
    _ad = null; // single-use

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        onClosed?.call();
        load(); // preload the next one for an instant re-show
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        _log.warn('Rewarded ad failed to show: ${err.message}');
        ad.dispose();
        onClosed?.call();
        load();
      },
    );
    await ad.show(onUserEarnedReward: (_, _) => onEarned?.call());
    return true;
  }

  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}
