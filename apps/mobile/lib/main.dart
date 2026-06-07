import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:persistent_device_id/persistent_device_id.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/constants/app_constants.dart';
import 'features/solver/presentation/providers/solver_providers.dart';

/// App entry point.
///
/// Loads [SharedPreferences] once and injects it into the [ProviderScope] so
/// every repository reads from a single, already-initialized instance (no async
/// gaps inside providers). Runs with zero configuration thanks to env defaults.
///
/// The Mobile Ads SDK + UMP consent are initialized lazily by
/// `mobileAdsProvider`, and the on-device engine net is downloaded by
/// `engineNetProvider` — both kicked off from the Home page on launch.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // GPLv3 compliance: the on-device Pikafish engine binary ships in the app, so
  // surface its license in the OS-standard "Open-source licenses" page.
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['Pikafish (on-device Xiangqi engine)'],
      'This app bundles the Pikafish Xiangqi engine, licensed under the GNU '
      'General Public License v3.0 (GPLv3). Because the engine is distributed in '
      'the app, this application is also offered under the GPLv3.\n\n'
      'Complete corresponding source for Pikafish: '
      'https://github.com/official-pikafish/Pikafish\n\n'
      'The NNUE evaluation network is downloaded at runtime from the official '
      'Pikafish Networks releases and is not distributed with the app. See '
      'LICENSE-engine in the project for the full notice and a written offer of '
      'source.',
    );
  });

  final prefs = await SharedPreferences.getInstance();
  await _resolveStableDeviceId(prefs);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const XiangqiSolverApp(),
    ),
  );
}

/// Seeds a reinstall-stable device id into [AppConstants.deviceIdPrefKey], so the
/// install-grant (free hints can't be farmed by reinstalling) and the per-device
/// rate limit both key off one stable value. `persistent_device_id` derives it
/// from MediaDrm on Android (survives uninstall/reinstall and re-signing). On an
/// unsupported platform or DRM failure it leaves whatever's stored — the
/// `deviceIdProvider` then falls back to a persisted random id.
Future<void> _resolveStableDeviceId(SharedPreferences prefs) async {
  try {
    final id = (await PersistentDeviceId.getDeviceId() ?? '').trim();
    if (id.length >= 8) {
      await prefs.setString(AppConstants.deviceIdPrefKey, id);
    }
  } catch (_) {
    // Unsupported platform / DRM unavailable → keep the existing/random id.
  }
}
