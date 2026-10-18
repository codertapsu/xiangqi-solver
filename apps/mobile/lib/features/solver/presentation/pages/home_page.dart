import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../../../../app/router.dart';
import '../../../../core/remote_config/remote_config_provider.dart';
import '../../../../core/utils/privacy_policy.dart';
import '../../../../core/widgets/action_tile.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../history/presentation/history_card.dart';
import '../../../monetization/presentation/banner_ad.dart';
import '../../../monetization/presentation/get_more_hints_sheet.dart';
import '../../../monetization/presentation/hint_balance_chip.dart';
import '../../../monetization/presentation/mobile_ads_provider.dart';
import '../../../onboarding/presentation/welcome_sheet.dart';
import '../../../settings/data/settings_repository.dart';
import '../../data/analysis_api.dart';
import '../../domain/solver_enums.dart';
import '../providers/engine_net_provider.dart';
import '../providers/share_intake_provider.dart';
import '../providers/solver_providers.dart';
import '../widgets/provider_dropdowns.dart';
import '../widgets/solver_hero.dart';
import '../widgets/solver_permissions_sheet.dart';

/// The landing screen: Solver Mode (Android) or share-in (iOS) as the hero,
/// a gallery-image fallback, the latest analysis, and a privacy footnote.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final TextEditingController _backendController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  StreamSubscription<String>? _analyzeSub;
  StreamSubscription<String>? _shareSub;
  AppLifecycleListener? _lifecycle;
  String? _healthLine;
  bool _testingConnection = false;

  /// iOS gets the share-in / pick-a-photo product shape instead of Solver Mode
  /// (no overlay-over-other-apps or on-demand capture on iOS — see docs/IOS_PORT.md).
  /// A getter (not a cached const) so widget tests can flip the target platform.
  bool get _isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _backendController.text = ref.read(settingsProvider).backendUrl;
    // Bridge native "analyze this screenshot" requests to upload + navigate.
    _analyzeSub = ref
        .read(solverModeProvider.notifier)
        .analyzeRequests
        .listen(_handleAnalyzeRequest);
    // iOS: a board screenshot shared in from another app runs the SAME flow.
    // (Inert off iOS — the stream never emits.)
    _shareSub = ref.read(shareIntakeProvider).imagePaths.listen(
      _handleAnalyzeRequest,
    );
    // Back from the system "display over other apps" screen (or anywhere):
    // finish a pending Solver Mode start and re-sync the running state, which
    // the notification's Stop action can change while we're away.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        final solver = ref.read(solverModeProvider.notifier);
        unawaited(solver.resumePendingStart());
        unawaited(solver.refreshRunning());
      },
    );
    // On app open: start the background on-device engine net download (it
    // self-gates if unsupported). The ads SDK waits for _firstFrame.
    ref.read(engineNetProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_firstFrame());
    });
  }

  /// First run: introduce the app and disclose where screenshots go before
  /// anything else. Then start the Mobile Ads SDK — its consent / tracking
  /// prompts must not stack on top of the welcome — and verify the active mode
  /// can actually run.
  Future<void> _firstFrame() async {
    if (!ref.read(settingsProvider).onboardingSeen) {
      await showWelcomeSheet(context);
      await ref
          .read(settingsProvider.notifier)
          .patch((s) => s.copyWith(onboardingSeen: true));
      if (!mounted) return;
    }
    ref.read(mobileAdsProvider); // consent + init; self-gates if unsupported
    await _checkModeHealth();
  }

  /// On startup (and after picking Cloud), make sure we're in a working mode.
  /// If Cloud is selected but the backend is unreachable, fall back to On-device
  /// when possible; if neither mode can run, tell the user how to fix it.
  Future<void> _checkModeHealth() async {
    final ModeCheckOutcome outcome;
    try {
      outcome = await ref.read(modeCoordinatorProvider).ensureUsableMode();
    } catch (_) {
      return; // never let a startup probe disrupt the UI
    }
    if (!mounted) return;
    switch (outcome) {
      case ModeCheckOutcome.ready:
        break;
      case ModeCheckOutcome.switchedToOnDevice:
        _snack(AppLocalizations.of(context).homeServerSwitchedOnDevice);
      case ModeCheckOutcome.noModeAvailable:
        await _showNoModeDialog();
    }
  }

  Future<void> _showNoModeDialog() {
    final l10n = AppLocalizations.of(context);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.cloud_off_outlined),
        title: Text(l10n.homeNoModeTitle),
        content: Text(l10n.homeNoModeBody),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(_checkModeHealth());
            },
            child: Text(l10n.actionRetry),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.actionClose),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              if (mounted) context.push(AppRoutes.settings);
            },
            child: Text(l10n.actionOpenSettings),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _backendController.dispose();
    _lifecycle?.dispose();
    unawaited(_analyzeSub?.cancel());
    unawaited(_shareSub?.cancel());
    super.dispose();
  }

  Future<void> _handleAnalyzeRequest(String path) async {
    await ref.read(analysisProvider.notifier).analyzeScreenshot(File(path));
    if (!mounted) return;
    _openResult();
  }

  /// Progressive solve: as soon as the streamed board stage lands, open the
  /// result page so the user sees the recognized position while the engine is
  /// still computing (the page renders [AnalysisLoading.board] reactively).
  void _maybeOpenResultEarly(AnalysisStatus status) {
    if (status is AnalysisLoading && status.board != null && mounted) {
      _openResult();
    }
  }

  /// Opens the result screen, but never stacks a second copy. The result page
  /// reads [analysisProvider] reactively, so when one is already showing (e.g.
  /// several captures in a row) it just refreshes in place. This keeps a single
  /// `/result` on the stack so system/AppBar back returns straight to Home
  /// instead of popping through one result per analysis.
  void _openResult() {
    final alreadyOnResult =
        GoRouter.of(context).state.uri.path == AppRoutes.result;
    if (!alreadyOnResult) unawaited(context.push(AppRoutes.result));
  }

  /// Start Solver Mode — explaining the two permissions first when Android is
  /// about to ask for them.
  Future<void> _startSolver() async {
    final solver = ref.read(solverModeProvider.notifier);
    if (!await solver.hasOverlayPermission()) {
      if (!mounted) return;
      if (!await showSolverPermissionsSheet(context)) return;
    }
    await solver.start();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testingConnection = true;
      _healthLine = null;
    });
    final result = await ref.read(analysisRepositoryProvider).checkHealth();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _testingConnection = false;
      _healthLine = result.when(
        success: (HealthStatus h) => l10n.backendHealthOk(
          h.version,
          h.latency.inMilliseconds,
          h.uptimeSeconds.toStringAsFixed(0),
        ),
        failure: (f) => l10n.backendHealthFailedShort,
      );
    });
  }

  Future<void> _pickAndAnalyze() async {
    final l10n = AppLocalizations.of(context);
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        // Match the vision model's own pixel budget (it downscales to ~2048px
        // anyway) and re-encode as JPEG: a 12 MP gallery photo shrinks from
        // several MB to a few hundred KB before upload, with no model-visible
        // quality loss.
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
      );
    } catch (e) {
      _snack(l10n.homeImagePickerError('$e'));
      return;
    }
    if (picked == null) return;
    await ref.read(analysisProvider.notifier).analyzeScreenshot(File(picked.path));
    if (!mounted) return;
    _openResult();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final solverMode = ref.watch(solverModeProvider);
    final analysisStatus = ref.watch(analysisProvider);
    final native = ref.watch(nativeSolverProvider);
    final remoteConfig = ref.watch(remoteConfigProvider);
    final history = ref.watch(historyListProvider);

    // Open the result page as soon as a streamed board stage lands.
    ref.listen<AnalysisStatus>(analysisProvider, (_, next) {
      _maybeOpenResultEarly(next);
    });

    // Surface transient solver-mode messages as snackbars.
    ref.listen(solverModeProvider, (prev, next) {
      final message = next.message;
      if (message != null && message != prev?.message) {
        _snack(message);
        ref.read(solverModeProvider.notifier).clearMessage();
      }
    });

    // Out of hints on a cloud solve → open the "get more hints" sheet.
    ref.listen(analysisProvider, (prev, next) {
      if (next is AnalysisError && next.failure.code == 'NO_HINTS') {
        showGetMoreHintsSheet(context);
      }
    });

    final isAnalyzing = analysisStatus is AnalysisLoading;
    final latest = history.isEmpty ? null : history.first;
    void setSide(SideToMove side) => ref
        .read(settingsProvider.notifier)
        .patch((s) => s.copyWith(mySide: side));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          // The device-local hint balance + "get more hints".
          const HintBalanceChip(),
          IconButton(
            tooltip: l10n.tooltipHistory,
            icon: const Icon(Icons.history_rounded),
            onPressed: () => context.push(AppRoutes.history),
          ),
          IconButton(
            tooltip: l10n.tooltipSettings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoutes.settings),
          ),
          const SizedBox(width: 4),
        ],
      ),
      // Anchored at the bottom, so it never pushes the main action down.
      bottomNavigationBar: const BannerAdWidget(),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            // Solver Mode is Android-only (floating overlay + on-demand capture);
            // iOS gets the share-in flow instead.
            if (native.isSupported)
              SolverHero(
                running: solverMode.isRunning,
                busy: solverMode.isBusy,
                side: settings.mySide,
                onSideChanged: setSide,
                onStart: () => unawaited(_startSolver()),
                onStop: () => unawaited(ref.read(solverModeProvider.notifier).stop()),
              )
            else if (_isIos)
              ShareHero(
                busy: isAnalyzing,
                side: settings.mySide,
                onSideChanged: setSide,
                onPick: () => unawaited(_pickAndAnalyze()),
              ),
            const SizedBox(height: 16),
            if (!_isIos)
              ActionTile(
                icon: Icons.add_photo_alternate_outlined,
                title: l10n.homeAnalyzeScreenshot,
                subtitle: isAnalyzing ? l10n.statusAnalyzing : l10n.homeAnalyzeScreenshotDesc,
                busy: isAnalyzing,
                onTap: () => unawaited(_pickAndAnalyze()),
              ),
            const SizedBox(height: 24),
            if (latest != null) ...[
              SectionHeader(
                l10n.homeRecent,
                action: TextButton(
                  onPressed: () => context.push(AppRoutes.history),
                  child: Text(l10n.homeSeeAll),
                ),
              ),
              HistoryCard(
                entry: latest,
                onTap: latest.result == null
                    ? () => context.push(AppRoutes.history)
                    : () => context.push(AppRoutes.historyEntry(latest.analysisId)),
              ),
              const SizedBox(height: 24),
            ] else if (native.isSupported && !solverMode.isRunning) ...[
              SectionHeader(l10n.homeHowItWorks),
              const _HowItWorks(),
              const SizedBox(height: 24),
            ],
            if (remoteConfig.showBackendSection || remoteConfig.showProvidersSection)
              SectionHeader(l10n.settingsGroupAdvanced),
            if (remoteConfig.showBackendSection) ...[
              _buildBackendCard(),
              const SizedBox(height: 16),
            ],
            if (remoteConfig.showProvidersSection) ...[
              _buildProvidersCard(settings),
              const SizedBox(height: 16),
            ],
            const _PrivacyNote(),
          ],
        ),
      ),
    );
  }

  Widget _buildBackendCard() {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.backendTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _backendController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l10n.backendUrlLabel,
                hintText: 'http://10.0.2.2:3000',
                prefixIcon: const Icon(Icons.link),
              ),
              onSubmitted: (value) => ref
                  .read(settingsProvider.notifier)
                  .patch((s) => s.copyWith(backendUrl: value.trim())),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testingConnection ? null : _testConnection,
                    icon: _testingConnection
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check),
                    label: Text(l10n.backendTestConnection),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () {
                    unawaited(
                      ref.read(settingsProvider.notifier).patch(
                        (s) => s.copyWith(
                          backendUrl: _backendController.text.trim(),
                        ),
                      ),
                    );
                    _snack(l10n.backendUrlSaved);
                  },
                  child: Text(l10n.actionSave),
                ),
              ],
            ),
            if (_healthLine != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                _healthLine!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProvidersCard(AppSettings settings) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(settingsProvider.notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.providersTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            AiProviderDropdown(
              value: settings.aiProvider,
              onChanged: (v) => notifier.patch((s) => s.copyWith(aiProvider: v)),
            ),
            const SizedBox(height: 12),
            EngineProviderDropdown(
              value: settings.engineProvider,
              onChanged: (v) =>
                  notifier.patch((s) => s.copyWith(engineProvider: v)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three numbered steps for people who haven't analyzed anything yet.
class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final steps = [l10n.homeStep1, l10n.homeStep2, l10n.homeStep3];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          children: [
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: s.secondaryContainer,
                      foregroundColor: s.onSecondaryContainer,
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: s.onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(steps[i], style: theme.textTheme.bodyMedium),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A quiet, always-present reminder of where screenshots go.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.lock_outline_rounded, size: 16, color: s.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${l10n.homePrivacyNote} '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: InkWell(
                      onTap: () => showPrivacyDetails(context),
                      child: Text(
                        l10n.homePrivacyDetails,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: s.primary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: s.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: s.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
