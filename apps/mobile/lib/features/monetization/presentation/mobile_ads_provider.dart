import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/remote_config/remote_config_provider.dart';
import '../../../core/utils/logger.dart';
import '../data/consent_manager.dart';
import 'app_open_ad_manager.dart';

/// Initializes the Mobile Ads SDK once (after UMP consent) and exposes a
/// readiness flag so ad widgets know when they may load. Also drives the
/// optional app-open ad on foreground (gated by the remote `appOpen` flag).
///
/// State is `true` once the SDK is initialized. Banner/app-open ads then load
/// against test or real units per the remote `useRealAds` flag; whether they SHOW
/// is gated by the remote config (banner/appOpen flags).
class MobileAdsController extends StateNotifier<bool> with WidgetsBindingObserver {
  MobileAdsController(this._ref) : super(false) {
    unawaited(_init());
  }

  final Ref _ref;
  static const AppLogger _log = AppLogger('MobileAds');
  AppOpenAdManager? _appOpen;
  bool _skippedFirstResume = false;

  Future<void> _init() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      await ConsentManager().gatherConsent();
      // iOS: App Tracking Transparency must be requested before the Mobile Ads
      // SDK may use the IDFA / SKAdNetwork attribution. No-op on Android.
      await _requestAppTrackingIfNeeded();
      await MobileAds.instance.initialize();
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(maxAdContentRating: MaxAdContentRating.g),
      );
      if (!mounted) return;
      state = true;
      _appOpen = AppOpenAdManager(
        useRealAds: _ref.read(remoteConfigProvider).useRealAds,
      );
      // Preload so the NEXT eligible resume can actually show an ad — the first
      // showAdIfAvailable() only kicks off a load and returns. Gate on the flag
      // so we don't waste requests while app-open ads are off (the default).
      if (_ref.read(remoteConfigProvider).appOpenAds) _appOpen!.loadAd();
      // We init asynchronously, so the cold-start resume usually fires BEFORE we
      // start observing. If we're already foreground now, treat that cold start
      // as consumed (don't skip the next, genuine resume); only skip when the
      // first resume we'll see is still the cold start.
      _skippedFirstResume =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      WidgetsBinding.instance.addObserver(this);
    } catch (e) {
      _log.warn('Mobile Ads init failed: $e');
    }
  }

  /// iOS App Tracking Transparency. Shows the system prompt once (only when the
  /// status is still undetermined); the user's choice gates IDFA use for ads.
  /// No-op on Android/other platforms and never throws into the init path.
  Future<void> _requestAppTrackingIfNeeded() async {
    if (!Platform.isIOS) return;
    try {
      final status =
          await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status == TrackingStatus.notDetermined) {
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
    } catch (e) {
      _log.warn('ATT request failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Skip the cold-start resume so the app-open ad doesn't cover the launch.
    if (!_skippedFirstResume) {
      _skippedFirstResume = true;
      return;
    }
    if (_ref.read(remoteConfigProvider).appOpenAds) {
      _appOpen?.showAdIfAvailable();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appOpen?.dispose();
    super.dispose();
  }
}

final mobileAdsProvider = StateNotifierProvider<MobileAdsController, bool>((ref) {
  return MobileAdsController(ref);
});
