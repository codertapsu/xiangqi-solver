import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/utils/logger.dart';
import '../data/ad_helper.dart';

/// Loads + shows an app-open ad on foreground (gated by remote config). Caches a
/// loaded ad for up to 4 hours and reloads after each show. Adapted from the
/// reference apps' AppOpenAdManager.
class AppOpenAdManager {
  AppOpenAdManager({this.useRealAds = false});

  static const AppLogger _log = AppLogger('AppOpenAd');
  static const Duration _maxCache = Duration(hours: 4);

  /// Whether to load the REAL ad unit (vs Google's test unit) — from remote config.
  final bool useRealAds;

  AppOpenAd? _ad;
  bool _showing = false;
  DateTime? _loadedAt;

  bool get _available =>
      _ad != null && _loadedAt != null && DateTime.now().difference(_loadedAt!) < _maxCache;

  void loadAd() {
    AppOpenAd.load(
      adUnitId: AdHelper.appOpenAdUnitId(useRealAds: useRealAds),
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loadedAt = DateTime.now();
        },
        onAdFailedToLoad: (err) {
          _log.warn('App-open ad failed to load: ${err.message}');
          _ad = null;
        },
      ),
    );
  }

  void showAdIfAvailable() {
    if (!_available) {
      loadAd();
      return;
    }
    if (_showing) return;
    final ad = _ad!;
    _ad = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => _showing = true,
      onAdDismissedFullScreenContent: (ad) {
        _showing = false;
        ad.dispose();
        loadAd();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        _showing = false;
        ad.dispose();
        loadAd();
      },
    );
    ad.show();
  }

  void dispose() => _ad?.dispose();
}
