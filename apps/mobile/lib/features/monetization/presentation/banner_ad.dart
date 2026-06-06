import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/remote_config/remote_config_provider.dart';
import '../data/ad_helper.dart';
import 'mobile_ads_provider.dart';

/// An adaptive anchored banner. Renders nothing until the SDK is ready, the
/// remote `bannerAds` flag is on, and an ad actually loads; on failure it
/// collapses to zero height. Designed to sit at the TOP of a page: it carries
/// its own bottom spacing when shown, so a collapsed banner leaves no gap.
class BannerAdWidget extends ConsumerStatefulWidget {
  const BannerAdWidget({super.key});

  @override
  ConsumerState<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends ConsumerState<BannerAdWidget> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _requested = false;

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_requested) return;
    _requested = true;
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    final width = MediaQuery.of(context).size.width.truncate();
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted) return;

    final ad = BannerAd(
      adUnitId: AdHelper.bannerAdUnitId(
        useRealAds: ref.read(remoteConfigProvider).useRealAds,
      ),
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) {
            setState(() => _loaded = true);
          } else {
            _ad?.dispose();
          }
        },
        onAdFailedToLoad: (ad, _) => ad.dispose(),
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  Widget build(BuildContext context) {
    final sdkReady = ref.watch(mobileAdsProvider);
    final bannersOn = ref.watch(remoteConfigProvider).bannerAds;
    if (!bannersOn || !sdkReady) return const SizedBox.shrink();

    // Start the load once the SDK is ready (guarded so it runs once).
    if (!_requested) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    if (!_loaded || _ad == null) return const SizedBox.shrink();

    // Own bottom spacing so a collapsed banner leaves no gap at the top.
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Center(
        child: SizedBox(
          width: _ad!.size.width.toDouble(),
          height: _ad!.size.height.toDouble(),
          child: AdWidget(ad: _ad!),
        ),
      ),
    );
  }
}
