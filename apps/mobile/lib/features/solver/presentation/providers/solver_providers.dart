import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/errors/failure.dart';
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

/// Stable, opaque per-install device id. Sent as the `x-device-id` header so the
/// backend can rate-limit per device (hints are a device-local counter now, so
/// this is the only abuse signal). Created lazily and persisted.
final deviceIdProvider = Provider<String>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  const key = 'device.id';
  final existing = prefs.getString(key);
  if (existing != null && existing.length >= 8) return existing;
  final rng = Random.secure();
  final id = base64UrlEncode(List<int>.generate(16, (_) => rng.nextInt(256)));
  unawaited(prefs.setString(key, id));
  return id;
});

/// Dio client kept in sync with the configured backend URL.
final dioClientProvider = Provider<DioClient>((ref) {
  final settings = ref.watch(settingsProvider);
  final client = DioClient(
    baseUrl: settings.backendUrl,
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
final onDeviceEngineProvider = FutureProvider<OnDeviceEngine>((ref) {
  final net = ref.watch(engineNetProvider);
  final nnuePath = net is EngineNetReady ? net.path : null;
  return ref.watch(onDeviceEngineResolverProvider).resolve(nnuePath);
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
          message: 'Solver mode started.',
        );
        // Mirror the current side onto the overlay's toggle.
        unawaited(_pushSideToOverlay());
      case SolverModeStoppedEvent():
        state = state.copyWith(
          isRunning: false,
          isBusy: false,
          lastEvent: event,
          message: 'Solver mode stopped.',
        );
      case ScreenshotCapturedEvent(:final path):
        state = state.copyWith(lastEvent: event, isBusy: false);
        _emitAnalyze(path);
      case ScreenshotFailedEvent(:final reason):
        state = state.copyWith(
          isBusy: false,
          lastEvent: event,
          message: 'Screenshot failed: $reason',
        );
      case PermissionDeniedEvent(:final permission):
        state = state.copyWith(
          isBusy: false,
          lastEvent: event,
          message: '${permission.name} permission was denied.',
        );
      case OverlayActionAnalyzeEvent():
        // The native overlay already captured one frame (captureOnce) and will
        // deliver it via a screenshotCaptured event — the SINGLE upload trigger.
        // We must NOT capture again here, or we'd upload twice and overwrite the
        // file mid-stream (the cause of the "Request aborted" errors).
        state = state.copyWith(
          lastEvent: event,
          isBusy: true,
          message: 'Analyzing…',
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
    state = state.copyWith(message: 'Side set to ${next.label}.');
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
        message: 'Solver mode requires a physical Android device.',
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
          message: 'Grant the overlay permission, then press Start again.',
        );
        return;
      }
      final projection = await _native.requestScreenCapturePermission();
      if (!projection) {
        state = state.copyWith(
          isBusy: false,
          message: 'Screen-capture permission is required to start.',
        );
        return;
      }
      await _native.startSolverMode();
      // Final state is confirmed by the solverModeStarted event.
    } catch (e) {
      state = state.copyWith(isBusy: false, message: 'Failed to start: $e');
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
      state = state.copyWith(isBusy: false, message: 'Failed to stop: $e');
    }
  }

  /// Manually capture a screenshot (used by some UI affordances).
  Future<String?> captureNow() async {
    if (!_native.isSupported) return null;
    try {
      return await _native.captureScreenshot();
    } catch (e) {
      state = state.copyWith(message: 'Capture failed: $e');
      return null;
    }
  }

  void clearMessage() => state = state.copyWith(clearMessage: true);

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
      state = const AnalysisError(
        UnknownFailure(
          'You\'re out of hints — watch an ad or buy a pack to keep analyzing.',
          code: 'NO_HINTS',
        ),
      );
      return;
    }

    state = const AnalysisLoading();
    final run = await _route(file, s);

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
        visionModel: s.onDeviceVisionModel,
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
          'Couldn\'t use your OpenAI key, so we read the board with ours (1 hint).',
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
                    'On-device engine couldn\'t find a move, so we used our cloud '
                        'engine (1 hint per ${_ref.read(remoteConfigProvider).ownKeyHintDivisor}).',
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
    await result.when(
      success: (value) async {
        final keepPath = _settings.storeScreenshots ? screenshotPath : null;
        state = AnalysisSuccess(value, screenshotPath: screenshotPath);
        _pushOverlayResult(value);
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
    final title = move != null ? move.human : 'No move found';
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
            title: 'Analysis failed',
            detail: failure.message,
            kind: 'error',
          )
          .catchError((Object _) {}),
    );
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
