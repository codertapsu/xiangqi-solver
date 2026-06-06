import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/utils/logger.dart';

/// Gathers user consent for ads via Google's User Messaging Platform (UMP).
///
/// Required for serving ads in the EEA/UK (and good practice everywhere). Call
/// [gatherConsent] before initializing the Mobile Ads SDK; it shows the consent
/// form when the user's region/status requires it, and resolves either way.
class ConsentManager {
  static const AppLogger _log = AppLogger('Consent');

  Future<void> gatherConsent() async {
    final completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
            if (error != null) _log.warn('Consent form: ${error.message}');
          });
        } catch (e) {
          _log.warn('Consent form failed: $e');
        }
        if (!completer.isCompleted) completer.complete();
      },
      (FormError error) {
        _log.warn('Consent info update failed: ${error.message}');
        if (!completer.isCompleted) completer.complete();
      },
    );
    return completer.future;
  }

  /// Whether ads may be requested given the current consent state.
  Future<bool> canRequestAds() async {
    try {
      return await ConsentInformation.instance.canRequestAds();
    } catch (_) {
      return true;
    }
  }
}
