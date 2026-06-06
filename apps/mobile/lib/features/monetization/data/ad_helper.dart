import 'dart:io' show Platform;

class _TestUnits {
  // Google's documented test units.
  static const bannerAndroid = 'ca-app-pub-3940256099942544/6300978111';
  static const bannerIos = 'ca-app-pub-3940256099942544/2435281174';
  static const rewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const rewardedIos = 'ca-app-pub-3940256099942544/1712485313';
  static const appOpenAndroid = 'ca-app-pub-3940256099942544/9257395921';
  static const appOpenIos = 'ca-app-pub-3940256099942544/5575463023';
}

class _RealUnits {
  // codertapsu publisher (pub-6124263664453069). iOS reuses Google's test units
  // until an iOS AdMob app is provisioned.
  static const bannerAndroid = 'ca-app-pub-6124263664453069/1354234833';
  static const bannerIos = 'ca-app-pub-3940256099942544/2435281174';
  static const rewardedAndroid = 'ca-app-pub-6124263664453069/8730164575';
  static const rewardedIos = 'ca-app-pub-3940256099942544/1712485313';
  static const appOpenAndroid = 'ca-app-pub-6124263664453069/9041153161';
  static const appOpenIos = 'ca-app-pub-3940256099942544/5575463023';
}

/// Resolves the ad unit ids. [useRealAds] selects between Google's TEST units
/// and the REAL Android units (provisioned under publisher pub-6124263664453069);
/// it comes from the backend remote-config flag `useRealAds` (default OFF), so a
/// build never serves real ads until the server enables it. iOS intentionally
/// stays on Google's test units (no iOS AdMob app yet).
///
/// NOTE: with real ads on, do NOT click your own ads while testing — register a
/// test device in AdMob (or keep the flag OFF) to avoid policy flags.
abstract final class AdHelper {
  static String _pick(
    bool useRealAds,
    String testAndroid,
    String testIos,
    String realAndroid,
    String realIos,
  ) {
    if (Platform.isAndroid) return useRealAds ? realAndroid : testAndroid;
    if (Platform.isIOS) return useRealAds ? realIos : testIos;
    throw UnsupportedError('Ads are only supported on Android/iOS.');
  }

  static String bannerAdUnitId({bool useRealAds = false}) => _pick(
    useRealAds,
    _TestUnits.bannerAndroid,
    _TestUnits.bannerIos,
    _RealUnits.bannerAndroid,
    _RealUnits.bannerIos,
  );

  static String rewardedAdUnitId({bool useRealAds = false}) => _pick(
    useRealAds,
    _TestUnits.rewardedAndroid,
    _TestUnits.rewardedIos,
    _RealUnits.rewardedAndroid,
    _RealUnits.rewardedIos,
  );

  static String appOpenAdUnitId({bool useRealAds = false}) => _pick(
    useRealAds,
    _TestUnits.appOpenAndroid,
    _TestUnits.appOpenIos,
    _RealUnits.appOpenAndroid,
    _RealUnits.appOpenIos,
  );
}
