import 'dart:ui' show Locale;

import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

/// Context-free access to the current [AppLocalizations] for code with no
/// `BuildContext` and no Riverpod `ref` — the data/network/on-device layers that
/// build user-facing error messages (shown later via `failure.message`).
///
/// The app root keeps [current] in sync with the active locale (see
/// `XiangqiSolverApp`). Before the root sets it (early startup or widget tests
/// that don't mount the root), it defaults to English so existing tests that
/// assert English error text keep passing; production sets the real locale long
/// before any data-layer error can be produced.
class AppL10n {
  AppL10n._();

  static AppLocalizations? _current;

  static AppLocalizations get current =>
      _current ?? lookupAppLocalizations(const Locale('en'));

  static set current(AppLocalizations value) => _current = value;
}
