import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'features/solver/presentation/providers/solver_providers.dart';

/// App entry point.
///
/// Loads [SharedPreferences] once and injects it into the [ProviderScope] so
/// every repository reads from a single, already-initialized instance (no async
/// gaps inside providers). Runs with zero configuration thanks to env defaults.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const XiangqiSolverApp(),
    ),
  );
}
