import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/l10n/app_l10n.dart';
import '../../../../core/l10n/enum_l10n.dart';
import '../../../../core/network/api_result.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/platform/method_channel_native_solver.dart';
import '../../../../core/platform/native_solver_event.dart';
import '../../../../core/platform/native_solver_platform.dart';
import '../../../../core/platform/noop_native_solver.dart';
import '../../../../core/remote_config/remote_config_provider.dart';
import '../../../../core/security/secure_key_store.dart';
import '../../../../core/utils/logger.dart';
import '../../../history/data/history_repository.dart';
import '../../../history/domain/history_entry.dart';
import '../../../monetization/presentation/wallet_providers.dart';
import '../../../settings/data/settings_repository.dart';
import '../../data/analysis_api.dart';
import '../../data/analysis_repository.dart';
import '../../data/ondevice/direct_openai_vision.dart';
import '../../data/ondevice/on_device_analyzer.dart';
import '../../data/ondevice/on_device_engine.dart';
import '../../data/ondevice/on_device_engine_resolver.dart';
import '../../domain/analysis_result.dart';
import '../../domain/board_state.dart';
import '../../domain/solver_enums.dart';
import 'engine_net_provider.dart';

const AppLogger _log = AppLogger('SolverProviders');

// ---------------------------------------------------------------------------
// Infrastructure providers
// ---------------------------------------------------------------------------

/// Supplied at app start via a [ProviderScope] override so widgets/tests can
/// inject a configured (or mocked) [SharedPreferences].
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in ProviderScope.',
  );
});

/// Native platform, chosen by host: real channel on Android, no-op elsewhere.
final nativeSolverProvider = Provider<NativeSolverPlatform>((ref) {
  final platform = defaultTargetPlatform == TargetPlatform.android && !kIsWeb
      ? MethodChannelNativeSolver()
      : const NoopNativeSolver();
  ref.onDispose(platform.dispose);
  return platform;
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(sharedPreferencesProvider));
});

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return HistoryRepository(ref.watch(sharedPreferencesProvider));
});

/// Stable, opaque per-device id. Sent as the `x-device-id` header so the backend
/// can rate-limit per device AND decide the install-grant (free hints can't be
/// farmed by reinstalling). Seeded at startup from a reinstall-stable id
/// (`persistent_device_id`, MediaDrm on Android — see `resolveStableDeviceId` in
/// main.dart); this provider just reads that persisted value, generating a random
/// fallback only if startup couldn't resolve one.
final deviceIdProvider = Provider<String>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  const key = AppConstants.deviceIdPrefKey;
  final existing = prefs.getString(key);
  if (existing != null && existing.length >= 8) return existing;
  final rng = Random.secure();
  final id = base64UrlEncode(List<int>.generate(16, (_) => rng.nextInt(256)));
  unawaited(prefs.setString(key, id));
  return id;
});

/// Dio client kept in sync with the configured backend URL.
///
/// Watches ONLY the backend URL (not the whole settings object): rebuilding
/// the client on every settings patch — overlay side toggles, slider drags,
/// language changes — closed the connection pool mid-session, so the next
/// solve paid a fresh TCP handshake.
final dioClientProvider = Provider<DioClient>((ref) {
  final backendUrl = ref.watch(settingsProvider.select((s) => s.backendUrl));
  final client = DioClient(
    baseUrl: backendUrl,
    deviceId: ref.watch(deviceIdProvider),
  );
  ref.onDispose(client.raw.close);
  return client;
});

final analysisApiProvider = Provider<AnalysisApi>((ref) {
  return AnalysisApi(ref.watch(dioClientProvider));
});

final analysisRepositoryProvider = Provider<AnalysisRepository>((ref) {
  return AnalysisRepository(ref.watch(analysisApiProvider));
});

/// Secure store for the user's own API key (On-device / BYO-key mode).
final secureKeyStoreProvider = Provider<SecureKeyStore>((ref) {
  return SecureKeyStore();
});

/// Resolves the bundled Pikafish + NNUE into a runnable engine (or an
/// unavailable stub off-device / when assets are missing).
final onDeviceEngineResolverProvider = Provider<OnDeviceEngineResolver>((ref) {
  return OnDeviceEngineResolver(ref.watch(nativeSolverProvider));
});

/// The resolved on-device engine. Recomputes when the downloaded net becomes
/// ready: the binary ships in the APK, the net is fetched at runtime
/// ([engineNetProvider]), so this is [UnavailableOnDeviceEngine] until both exist.
///
/// The engine instance is CACHED by this provider across solves, so its warm
/// UCI session (process + loaded NNUE) is reused; disposal on rebuild releases
/// the old session's memory.
final onDeviceEngineProvider = FutureProvider<OnDeviceEngine>((ref) async {
  final net = ref.watch(engineNetProvider);
  final nnuePath = net is EngineNetReady ? net.path : null;
  final engine = await ref.watch(onDeviceEngineResolverProvider).resolve(nnuePath);
  ref.onDispose(engine.dispose);
  return engine;
});

/// Direct OpenAI vision client (BYO key) for the on-device path.
final boardVisionClientProvider = Provider<BoardVisionClient>((ref) {
  return DirectOpenAiVisionClient();
});

/// Coordinates the experimental On-device (Offline) analysis path. The engine
/// is resolved per-request (see [onDeviceEngineProvider]) and passed in.
final onDeviceAnalyzerProvider = Provider<OnDeviceAnalyzer>((ref) {
  return OnDeviceAnalyzer(
    ref.watch(secureKeyStoreProvider),
    ref.watch(boardVisionClientProvider),
  );
});

/// Outcome of a [ModeCoordinator.ensureUsableMode] check.
enum ModeCheckOutcome {
  /// The active mode can run as-is (Cloud backend healthy, or On-device chosen).
  ready,

  /// Cloud was selected but the backend is down; switched to On-device (a BYO
  /// key is present). The UI should tell the user.
  switchedToOnDevice,

  /// Neither mode is usable: the backend is down AND On-device has no API key.
  noModeAvailable,
}

/// Keeps the app in a *usable* analysis mode. In Cloud mode it pings the
/// backend; when it's down it falls back to On-device (if a BYO OpenAI key is
/// set), otherwise reports that no mode is usable. On-device mode is
/// self-contained, so it's always considered ready (the analyzer surfaces a
/// missing key at run time).
class ModeCoordinator {
  ModeCoordinator(this._ref);

  final Ref _ref;

  Future<ModeCheckOutcome> ensureUsableMode() async {
    final s = _ref.read(settingsProvider);
    // Fully local (own key + on-device engine) needs no backend; engine
    // readiness surfaces at run time (a board-only result with a warning).
    if (s.isFullyLocal) return ModeCheckOutcome.ready;

    // Any backend-using combo needs the backend reachable.
    if (await _backendHealthy()) return ModeCheckOutcome.ready;

    // Backend down → fall back to fully-local if the user has their own key.
    if (await _hasApiKey()) {
      await _ref.read(settingsProvider.notifier).patch(
        (st) => st.copyWith(
          aiKeySource: AiKeySource.own,
          engineLocation: EngineLocation.onDevice,
        ),
      );
      return ModeCheckOutcome.switchedToOnDevice;
    }
    return ModeCheckOutcome.noModeAvailable;
  }

  Future<bool> _backendHealthy() async {
    try {
      final result = await _ref
          .read(analysisRepositoryProvider)
          .checkHealth()
          .timeout(const Duration(seconds: 6));
      return result.isSuccess;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasApiKey() async {
    try {
      return await _ref.read(secureKeyStoreProvider).hasOpenAiKey();
    } catch (_) {
      return false;
    }
  }
}

final modeCoordinatorProvider = Provider<ModeCoordinator>((ref) {
  return ModeCoordinator(ref);
});

// ---------------------------------------------------------------------------
// Settings state
// ---------------------------------------------------------------------------

/// Holds the current [AppSettings] and persists every mutation.
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(this._repository) : super(_repository.load());

  final SettingsRepository _repository;

  Future<void> update(AppSettings settings) async {
    state = await _repository.save(settings);
  }

  Future<void> patch(AppSettings Function(AppSettings) transform) {
    return update(transform(state));
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
      return SettingsNotifier(ref.watch(settingsRepositoryProvider));
    });

// ---------------------------------------------------------------------------
// Solver-mode state + native event bridge
// ---------------------------------------------------------------------------

/// UI-facing state of solver mode and the most recent native signal.
class SolverModeState extends Equatable {
  const SolverModeState({
    this.isRunning = false,
    this.isBusy = false,
    this.lastEvent,
    this.message,
  });

  final bool isRunning;
  final bool isBusy;
  final NativeSolverEvent? lastEvent;

  /// A transient user-facing message (e.g. permission denied).
  final String? message;

  SolverModeState copyWith({
    bool? isRunning,
    bool? isBusy,
    NativeSolverEvent? lastEvent,
    String? message,
    bool clearMessage = false,
  }) {
    return SolverModeState(
      isRunning: isRunning ?? this.isRunning,
      isBusy: isBusy ?? this.isBusy,
      lastEvent: lastEvent ?? this.lastEvent,
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  @override
  List<Object?> get props => [isRunning, isBusy, lastEvent, message];
}

/// Drives solver mode: relays commands to native, listens to native events,
/// and exposes a clean [SolverModeState] to the UI.
///
/// When the overlay "Analyze" action fires or a screenshot is captured, it
/// emits the file path on [analyzeRequests] so a listener can upload + route.
class SolverModeNotifier extends StateNotifier<SolverModeState> {
  SolverModeNotifier(this._ref, this._native) : super(const SolverModeState()) {
    _subscribe();
    unawaited(refreshRunning());
  }

  final Ref _ref;
  final NativeSolverPlatform _native;
  StreamSubscription<NativeSolverEvent>? _eventSub;

  final StreamController<String> _analyzeRequests =
      StreamController<String>.broadcast();

  /// Absolute screenshot paths that should be analyzed (overlay action /
  /// capture-complete). Listened to by the app shell to upload + navigate.
  Stream<String> get analyzeRequests => _analyzeRequests.stream;

  bool get isSupported => _native.isSupported;

  void _subscribe() {
    _eventSub = _native.events.listen(
      _onEvent,
      onError: (Object e) => _log.warn('Native event error: $e'),
    );
  }

  void _onEvent(NativeSolverEvent event) {
    switch (event) {
      case SolverModeStartedEvent():
        state = state.copyWith(
          isRunning: true,
          isBusy: false,
          lastEvent: event,
          message: AppL10n.current.solverStarted,
        );
        // Mirror the current side onto the overlay's toggle.
        unawaited(_pushSideToOverlay());
      case SolverModeStoppedEvent():
        state = state.copyWith(
          isRunning: false,
          isBusy: false,
          lastEvent: event,
          message: AppL10n.current.solverStopped,
        );
      case ScreenshotCapturedEvent(:final path):
        // Keep isBusy: the capture is only the START of the real wait
        // (upload + vision + engine). AnalysisNotifier clears it when the
        // analysis settles, so progress indicators span the whole solve.
        state = state.copyWith(lastEvent: event, isBusy: true);
        _emitAnalyze(path);
      case ScreenshotFailedEvent(:final reason):
        state = state.copyWith(
          isBusy: false,
          lastEvent: event,
          message: AppL10n.current.solverScreenshotFailed(reason),
        );
      case PermissionDeniedEvent(:final permission):
        state = state.copyWith(
          isBusy: false,
          lastEvent: event,
          message: AppL10n.current.solverPermissionDenied(permission.name),
        );
      case OverlayActionAnalyzeEvent():
        // The native overlay already captured one frame (captureOnce) and will
        // deliver it via a screenshotCaptured event — the SINGLE upload trigger.
        // We must NOT capture again here, or we'd upload twice and overwrite the
        // file mid-stream (the cause of the "Request aborted" errors).
        state = state.copyWith(
          lastEvent: event,
          isBusy: true,
          message: AppL10n.current.statusAnalyzing,
        );
      case OverlayActionStopEvent():
        state = state.copyWith(lastEvent: event);
        unawaited(stop());
      case OverlayActionSwitchSideEvent():
        state = state.copyWith(lastEvent: event);
        _enqueueSideToggle();
      case UnknownEvent():
        state = state.copyWith(lastEvent: event);
    }
  }

  /// Pushes the current `mySide` setting onto the overlay's side toggle.
  Future<void> _pushSideToOverlay() async {
    final side = _ref.read(settingsProvider).mySide;
    try {
      await _native.setOverlaySide(side.wireValue);
    } catch (_) {
      // Overlay may not be showing; ignore.
    }
  }

  /// Serializes side toggles so rapid double-taps don't race the read-modify-
  /// write on the persisted setting (which would drop a toggle).
  Future<void> _sideQueue = Future<void>.value();

  void _enqueueSideToggle() {
    _sideQueue = _sideQueue.then((_) => _toggleSide()).catchError((Object _) {});
  }

  /// Flips the user's side (Red <-> Black), persists it, and echoes the new side
  /// back to the overlay toggle. The next analysis solves for the new side.
  Future<void> _toggleSide() async {
    final current = _ref.read(settingsProvider).mySide;
    final next = current == SideToMove.red ? SideToMove.black : SideToMove.red;
    await _ref
        .read(settingsProvider.notifier)
        .patch((s) => s.copyWith(mySide: next));
    final l10n = AppL10n.current;
    state = state.copyWith(message: l10n.solverSideSet(next.localizedLabel(l10n)));
    await _pushSideToOverlay();
  }

  void _emitAnalyze(String path) {
    if (path.isEmpty) return;
    if (!_analyzeRequests.isClosed) _analyzeRequests.add(path);
  }

  /// Re-reads the live running state from native.
  Future<void> refreshRunning() async {
    if (!_native.isSupported) return;
    try {
      final running = await _native.isSolverModeRunning();
      state = state.copyWith(isRunning: running);
    } catch (e) {
      _log.warn('refreshRunning failed: $e');
    }
  }

  /// Ensures overlay + projection permissions, then starts solver mode.
  Future<void> start() async {
    if (!_native.isSupported) {
      state = state.copyWith(
        message: AppL10n.current.solverNeedsPhysicalDevice,
      );
      return;
    }
    state = state.copyWith(isBusy: true, clearMessage: true);
    try {
      final hasOverlay = await _native.checkOverlayPermission();
      if (!hasOverlay) {
        await _native.requestOverlayPermission();
        state = state.copyWith(
          isBusy: false,
          message: AppL10n.current.solverGrantOverlay,
        );
        return;
      }
      final projection = await _native.requestScreenCapturePermission();
      if (!projection) {
        state = state.copyWith(
          isBusy: false,
          message: AppL10n.current.solverNeedCapturePermission,
        );
        return;
      }
      await _native.startSolverMode();
      // Final state is confirmed by the solverModeStarted event.
    } catch (e) {
      state = state.copyWith(
        isBusy: false,
        message: AppL10n.current.solverFailedStart('$e'),
      );
    }
  }

  Future<void> stop() async {
    if (!_native.isSupported) {
      state = state.copyWith(isRunning: false);
      return;
    }
    state = state.copyWith(isBusy: true, clearMessage: true);
    try {
      await _native.stopSolverMode();
    } catch (e) {
      state = state.copyWith(
        isBusy: false,
        message: AppL10n.current.solverFailedStop('$e'),
      );
    }
  }

  /// Manually capture a screenshot (used by some UI affordances).
  Future<String?> captureNow() async {
    if (!_native.isSupported) return null;
    try {
      return await _native.captureScreenshot();
    } catch (e) {
      state = state.copyWith(message: AppL10n.current.solverCaptureFailed('$e'));
      return null;
    }
  }

  void clearMessage() => state = state.copyWith(clearMessage: true);

  /// Lets the analysis flow keep the busy indicator honest: it stays on from
  /// capture until the solve settles (see [AnalysisNotifier._apply]).
  void setBusy(bool value) {
    if (state.isBusy != value) state = state.copyWith(isBusy: value);
  }

  @override
  void dispose() {
    unawaited(_eventSub?.cancel());
    unawaited(_analyzeRequests.close());
    super.dispose();
  }
}

final solverModeProvider =
    StateNotifierProvider<SolverModeNotifier, SolverModeState>((ref) {
      return SolverModeNotifier(ref, ref.watch(nativeSolverProvider));
    });

// ---------------------------------------------------------------------------
// Analysis run state (last result + in-flight status)
// ---------------------------------------------------------------------------

/// Status of the most recent analysis request.
sealed class AnalysisStatus extends Equatable {
  const AnalysisStatus();

  @override
  List<Object?> get props => const [];
}

class AnalysisIdle extends AnalysisStatus {
  const AnalysisIdle();
}

class AnalysisLoading extends AnalysisStatus {
  const AnalysisLoading();
}

class AnalysisSuccess extends AnalysisStatus {
  const AnalysisSuccess(this.result, {this.screenshotPath});

  final AnalysisResult result;
  final String? screenshotPath;

  @override
  List<Object?> get props => [result, screenshotPath];
}

class AnalysisError extends AnalysisStatus {
  const AnalysisError(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

/// Coordinates analysis requests, surfacing loading/success/error and recording
/// successful runs in history.
class AnalysisNotifier extends StateNotifier<AnalysisStatus> {
  AnalysisNotifier(this._ref) : super(const AnalysisIdle());

  final Ref _ref;

  AnalysisRepository get _repo => _ref.read(analysisRepositoryProvider);
  AppSettings get _settings => _ref.read(settingsProvider);
  HistoryRepository get _history => _ref.read(historyRepositoryProvider);

  EngineOptions get _engineOptions => EngineOptions(
    engineProvider: _settings.engineProvider,
    engineDepth: _settings.engineDepth,
    engineMoveTimeMs: _settings.engineMoveTimeMs,
    engineMultiPv: _settings.engineMultiPv,
    engineThreads: _settings.engineThreads,
    engineHashMb: _settings.engineHashMb,
  );

  /// Analyzes [file], routing across the 2x2 of AI-key source x engine location.
  ///
  /// Hints are consumed only when the backend is involved: our key = 1 hint per
  /// analysis; the user's own key + our cloud engine = 1 hint per
  /// `ownKeyDivisor` analyses; fully-local (own key + on-device engine) = none.
  /// An empty wallet surfaces a `NO_HINTS` failure (the UI opens the "get more
  /// hints" sheet); a hint is only charged for a SUCCESSFUL result.
  Future<void> analyzeScreenshot(File file) async {
    final s = _settings;
    final wallet = _ref.read(walletProvider.notifier);

    if (s.usesBackend && !wallet.canSpend()) {
      final failure = UnknownFailure(
        AppL10n.current.hintsOutOfHints,
        code: 'NO_HINTS',
      );
      state = AnalysisError(failure);
      _ref.read(solverModeProvider.notifier).setBusy(false);
      // The overlay showed "Analyzing…" on the tap — settle it too, or a
      // Solver-Mode user out of hints watches a spinner forever.
      _pushOverlayError(failure);
      return;
    }

    state = const AnalysisLoading();
    final _RunOutcome run;
    try {
      run = await _route(file, s);
    } catch (e) {
      // _route's legs normally return ApiResult failures, but an unexpected
      // throw (e.g. the engine-resolver future erroring) must not wedge the
      // Loading state and the solver-mode busy indicator forever.
      _log.warn('Analysis route threw: $e');
      await _apply(
        ApiResult.failure(UnknownFailure('$e', code: 'ANALYSIS_FAILED')),
        screenshotPath: file.path,
      );
      return;
    }

    // Charge by what ACTUALLY ran (after any backend fallback), not the
    // originally-selected mode: our OpenAI key reading the board = 1 full hint;
    // own key + our cloud engine = 1 hint per N; fully local = nothing.
    if (run.result.isSuccess) {
      if (run.usedOurVision) {
        wallet.spend();
      } else if (run.usedOurEngine) {
        wallet.spendForOwnKey(_ref.read(remoteConfigProvider).ownKeyHintDivisor);
      }
    }
    await _apply(run.result, screenshotPath: file.path);
  }

  /// Routes the analysis across the 2x2 (AI-key source x engine location) with
  /// automatic fallback to OUR backend whenever the user's own resources fail:
  ///  - own-key vision that errors (missing/invalid key, request failure) falls
  ///    back to our server vision (then charged as a full hint);
  ///  - the on-device engine returning no usable best move falls back to our
  ///    cloud engine.
  /// The returned [_RunOutcome] records what ACTUALLY ran so the caller charges
  /// the right number of hints. Fallbacks that would cost a hint are only taken
  /// when the wallet can afford them.
  Future<_RunOutcome> _route(File file, AppSettings s) async {
    final wallet = _ref.read(walletProvider.notifier);
    final ours = s.aiKeySource == AiKeySource.ours;
    final cloud = s.engineLocation == EngineLocation.cloud;
    final analyzer = _ref.read(onDeviceAnalyzerProvider);

    // our key + cloud engine → one fused backend call; nothing to fall back to.
    if (ours && cloud) {
      final r = await _repo.analyzeScreenshot(
        file,
        provider: s.aiProvider,
        sideToMove: s.mySide,
        language: s.language,
        options: _engineOptions,
      );
      return _RunOutcome(r, usedOurVision: true, usedOurEngine: true);
    }

    // ---- VISION STAGE: our server key, or the user's own key (→ server fallback).
    final BoardState board;
    final List<String> visionWarnings;
    final ProviderStatus visionStatus;
    final bool usedOurVision;

    if (ours) {
      final r = await _backendVision(file, s);
      final v = r.valueOrNull;
      if (v == null) {
        return _RunOutcome(
          ApiResult.failure(r.failureOrNull!),
          usedOurVision: true,
          usedOurEngine: false,
        );
      }
      board = v.board;
      visionWarnings = v.warnings;
      visionStatus = _ourServerVision;
      usedOurVision = true;
    } else {
      final own = await analyzer.extractBoardOwnKey(
        file,
        sideToMove: s.mySide,
        // User override if set, else the backend-configured default (gpt-5.4).
        visionModel: s.onDeviceVisionModelOr(
          _ref.read(remoteConfigProvider).onDeviceVisionModel,
        ),
      );
      final ownVision = own.valueOrNull;
      if (ownVision != null) {
        board = ownVision.board;
        visionWarnings = ownVision.warnings;
        visionStatus = const ProviderStatus(provider: 'openai (your key)', ok: true);
        usedOurVision = false;
      } else {
        // Own-key vision failed (no/invalid key, request error) → fall back to
        // our server vision, but only when the user can pay the full hint.
        if (!wallet.canSpend()) {
          return _RunOutcome(
            ApiResult.failure(own.failureOrNull!),
            usedOurVision: false,
            usedOurEngine: false,
          );
        }
        final r = await _backendVision(file, s);
        final v = r.valueOrNull;
        if (v == null) {
          return _RunOutcome(
            ApiResult.failure(r.failureOrNull!),
            usedOurVision: true,
            usedOurEngine: false,
          );
        }
        board = v.board;
        visionWarnings = [
          AppL10n.current.fallbackOwnKeyVision,
          ...v.warnings,
        ];
        visionStatus = _ourServerVision;
        usedOurVision = true;
      }
    }

    // ---- ENGINE STAGE: our cloud engine, or on-device (→ cloud fallback).
    if (cloud) {
      final r = await _backendEngine(board, s);
      return _RunOutcome(r, usedOurVision: usedOurVision, usedOurEngine: r.isSuccess);
    }

    final engine = await _ref.read(onDeviceEngineProvider.future);
    final local = await analyzer.solveLocally(
      board,
      engine: engine,
      visionStatus: visionStatus,
      language: s.language,
      depth: s.engineDepth,
      threads: s.engineThreads,
      hashMb: s.engineHashMb,
      multiPv: s.engineMultiPv,
      warnings: visionWarnings,
    );
    if (local.valueOrNull?.bestMove != null) {
      return _RunOutcome(local, usedOurVision: usedOurVision, usedOurEngine: false);
    }

    // On-device engine produced no usable move (unavailable / illegal / error) →
    // retry on our cloud engine. Allowed when the vision was already ours (so it
    // was paid for) or the user can afford the discounted engine hint.
    if (usedOurVision || wallet.canSpend()) {
      final r = await _backendEngine(board, s);
      if (r.valueOrNull?.bestMove != null) {
        // When the vision was the user's own key, this fallback is the ONLY
        // thing that costs a hint (1 per N) — disclose it on the result so a
        // run the UI labelled "no hints used" doesn't charge silently.
        final result = usedOurVision
            ? r
            : r.map(
                (res) => res.copyWith(
                  warnings: [
                    AppL10n.current.fallbackOnDeviceEngine(
                      _ref.read(remoteConfigProvider).ownKeyHintDivisor,
                    ),
                    ...res.warnings,
                  ],
                ),
              );
        return _RunOutcome(result, usedOurVision: usedOurVision, usedOurEngine: true);
      }
    }
    // Both engines came up empty → keep the friendlier on-device (board-only)
    // result, which already carries an honest "why" warning.
    return _RunOutcome(local, usedOurVision: usedOurVision, usedOurEngine: false);
  }

  static const ProviderStatus _ourServerVision =
      ProviderStatus(provider: 'openai (our key, server)', ok: true);

  /// Board recognition on our server with OUR key (POST /analysis/extract).
  Future<ApiResult<({BoardState board, List<String> warnings})>> _backendVision(
    File file,
    AppSettings s,
  ) {
    return _repo.extractBoard(file, provider: s.aiProvider, sideToMove: s.mySide);
  }

  /// Best move from our cloud engine on a recognized board (POST /analysis/board).
  Future<ApiResult<AnalysisResult>> _backendEngine(BoardState board, AppSettings s) {
    return _repo.analyzeBoard(
      sideToMove: board.sideToMove,
      pieces: board.pieces,
      provider: s.aiProvider,
      language: s.language,
      options: _engineOptions,
    );
  }

  /// Runs the engine directly on the supplied board (bypasses vision).
  Future<void> analyzeBoard(AnalysisResult sourceBoard) async {
    state = const AnalysisLoading();
    final result = await _repo.analyzeBoard(
      sideToMove: sourceBoard.board.sideToMove,
      pieces: sourceBoard.board.pieces,
      provider: _settings.aiProvider,
      language: _settings.language,
      options: _engineOptions,
    );
    await _apply(result);
  }

  Future<void> _apply(
    ApiResult<AnalysisResult> result, {
    String? screenshotPath,
  }) async {
    // The solve settled (either way) — release the solver-mode busy indicator
    // that has been on since capture.
    _ref.read(solverModeProvider.notifier).setBusy(false);
    await result.when(
      success: (value) async {
        state = AnalysisSuccess(value, screenshotPath: screenshotPath);
        _pushOverlayResult(value);
        // Persist the screenshot into history-owned storage (NOT the transient
        // capture cache, which is pruned to the last few frames, nor a picker/
        // share temp file) so older history entries keep a viewable image.
        final keepPath = _settings.storeScreenshots
            ? await _persistHistoryScreenshot(value.analysisId, screenshotPath)
            : null;
        await _recordHistory(value, keepPath);
      },
      failure: (failure) async {
        _log.warn('Analysis failed: ${failure.message}');
        state = AnalysisError(failure);
        _pushOverlayError(failure);
      },
    );
  }

  /// Mirror the best move into the floating overlay so a Solver-Mode user sees
  /// it without switching back to the app. A no-op off Android / when no
  /// overlay is showing.
  void _pushOverlayResult(AnalysisResult value) {
    final native = _ref.read(nativeSolverProvider);
    if (!native.isSupported) return;
    final move = value.bestMove;
    final title = move != null ? move.human : AppL10n.current.statusNoMove;
    final detail = move != null
        ? '${move.notation}  •  ${move.score}'
        : (value.warnings.isNotEmpty ? value.warnings.first : null);
    unawaited(
      native
          .updateOverlay(title: title, detail: detail, kind: 'result')
          .catchError((Object _) {}),
    );
  }

  void _pushOverlayError(Failure failure) {
    final native = _ref.read(nativeSolverProvider);
    if (!native.isSupported) return;
    unawaited(
      native
          .updateOverlay(
            title: AppL10n.current.statusAnalysisFailed,
            detail: failure.message,
            kind: 'error',
          )
          .catchError((Object _) {}),
    );
  }

  /// Copies the analysed screenshot into a persistent, history-owned directory
  /// keyed by [analysisId] and returns the new path.
  ///
  /// The source is a TRANSIENT file: the Android capture pipeline keeps only the
  /// last few frames in its cache (CAPTURE_KEEP_FILES), and the gallery picker /
  /// iOS share use temp files. So a history entry must own its own copy, or it
  /// would render as "unavailable" once the source is pruned/overwritten. The
  /// [HistoryRepository] deletes these copies when an entry drops past the cap or
  /// history is cleared, so storage stays bounded. Best-effort: on failure it
  /// falls back to the source path (no worse than before) rather than throwing.
  Future<String?> _persistHistoryScreenshot(
    String analysisId,
    String? sourcePath,
  ) async {
    if (sourcePath == null || sourcePath.isEmpty) return null;
    try {
      final src = File(sourcePath);
      if (!src.existsSync()) return null;
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/history_screenshots');
      await dir.create(recursive: true);
      // Guard against an empty/garbage id (on-device results may not carry a
      // UUID): a constant dest like "<dir>/.jpg" would make every fully-local
      // solve overwrite the same file.
      final rawId = analysisId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final safeId = rawId.isEmpty
          ? 'local_${DateTime.now().millisecondsSinceEpoch}'
          : rawId;
      // Preserve the source encoding: captures are JPEG now, picker/share
      // files can be either. (Flutter decodes by magic bytes, but a truthful
      // extension keeps the files debuggable.)
      final lower = sourcePath.toLowerCase();
      final ext = lower.endsWith('.jpg') || lower.endsWith('.jpeg') ? '.jpg' : '.png';
      final dest = '${dir.path}/$safeId$ext';
      if (dest != src.path) await src.copy(dest);
      // Keep only the last N (server-configurable) screenshots on disk, so
      // storage tracks the retention shown to the user in Settings.
      await _pruneHistoryScreenshots(
        dir,
        _ref.read(remoteConfigProvider).storedScreenshotsMax,
      );
      return dest;
    } catch (e) {
      _log.warn('Failed to persist history screenshot: $e');
      return sourcePath;
    }
  }

  /// Keeps only the [keep] most-recent screenshots in [dir], deleting the rest
  /// so on-disk storage tracks the server-configured retention. Best-effort.
  Future<void> _pruneHistoryScreenshots(Directory dir, int keep) async {
    final n = keep < 0 ? 0 : keep;
    try {
      final files = dir.listSync().whereType<File>().toList();
      if (files.length <= n) return;
      final mtimes = {for (final f in files) f.path: f.lastModifiedSync()};
      files.sort((a, b) => mtimes[b.path]!.compareTo(mtimes[a.path]!));
      for (final old in files.skip(n)) {
        try {
          await old.delete();
        } catch (_) {}
      }
    } catch (e) {
      _log.warn('Failed to prune history screenshots: $e');
    }
  }

  Future<void> _recordHistory(AnalysisResult result, String? path) async {
    try {
      await _history.add(
        HistoryEntry.fromResult(result, screenshotPath: path),
      );
    } catch (e) {
      _log.warn('Failed to record history: $e');
    }
  }

  void reset() => state = const AnalysisIdle();
}

/// What actually ran to produce an analysis (after any backend fallbacks), so
/// the hint charge reflects reality rather than the originally-selected mode.
class _RunOutcome {
  const _RunOutcome(
    this.result, {
    required this.usedOurVision,
    required this.usedOurEngine,
  });

  final ApiResult<AnalysisResult> result;

  /// Our OpenAI key read the board (the expensive step → a full hint).
  final bool usedOurVision;

  /// Our cloud engine computed the move (→ a discounted hint when the vision
  /// was the user's own key).
  final bool usedOurEngine;
}

final analysisProvider =
    StateNotifierProvider<AnalysisNotifier, AnalysisStatus>((ref) {
      return AnalysisNotifier(ref);
    });

/// Convenience: the last successful result, or null.
final lastResultProvider = Provider<AnalysisResult?>((ref) {
  final status = ref.watch(analysisProvider);
  return status is AnalysisSuccess ? status.result : null;
});

/// History list, recomputed whenever an analysis succeeds.
final historyListProvider = Provider<List<HistoryEntry>>((ref) {
  // Depend on analysis status so the list refreshes after a new entry.
  ref.watch(analysisProvider);
  return ref.watch(historyRepositoryProvider).loadAll();
});
