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
import '../../../monetization/presentation/banner_ad.dart';
import '../../../monetization/presentation/get_more_hints_sheet.dart';
import '../../../monetization/presentation/hint_balance_chip.dart';
import '../../../monetization/presentation/mobile_ads_provider.dart';
import '../../../settings/data/settings_repository.dart';
import '../../data/analysis_api.dart';
import '../providers/engine_net_provider.dart';
import '../providers/share_intake_provider.dart';
import '../providers/solver_providers.dart';
import '../widgets/privacy_banner.dart';
import '../widgets/provider_dropdowns.dart';
import '../widgets/section_card.dart';
import '../widgets/side_selector.dart';

/// The app's landing screen: solver-mode controls, backend configuration,
/// connection testing, and a mock "pick image & analyze" flow.
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
    // On app open: kick off the Mobile Ads SDK (consent + init) and the
    // background on-device engine net download (both self-gate if unsupported).
    ref.read(mobileAdsProvider);
    ref.read(engineNetProvider);
    // On app open, verify the active mode can actually run (see _checkModeHealth).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_checkModeHealth());
    });
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
    unawaited(_analyzeSub?.cancel());
    unawaited(_shareSub?.cancel());
    super.dispose();
  }

  Future<void> _handleAnalyzeRequest(String path) async {
    await ref.read(analysisProvider.notifier).analyzeScreenshot(File(path));
    if (!mounted) return;
    _openResult();
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

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          // Hint balance + "get more hints" — only when the backend is used
          // (our key OR cloud engine). Fully-local mode consumes no hints.
          const HintBalanceChip(),
          IconButton(
            tooltip: l10n.tooltipHistory,
            icon: const Icon(Icons.history),
            onPressed: () => context.push(AppRoutes.history),
          ),
          IconButton(
            tooltip: l10n.tooltipSettings,
            icon: const Icon(Icons.settings),
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const BannerAdWidget(),
            const PrivacyBanner(),
            const SizedBox(height: 16),
            // Solver Mode is Android-only (floating overlay + on-demand capture);
            // iOS shows the share-in flow instead, other unsupported hosts nothing.
            if (native.isSupported) ...[
              _buildSolverModeCard(solverMode, native.isSupported),
              const SizedBox(height: 16),
            ] else if (_isIos) ...[
              _buildShareHintCard(),
              const SizedBox(height: 16),
            ],
            if (remoteConfig.showBackendSection) ...[
              _buildBackendCard(settings),
              const SizedBox(height: 16),
            ],
            if (remoteConfig.showProvidersSection) ...[
              _buildProvidersCard(settings),
              const SizedBox(height: 16),
            ],
            _buildSideCard(settings),
            const SizedBox(height: 16),
            _buildMockTestCard(isAnalyzing),
          ],
        ),
      ),
    );
  }

  Widget _buildSolverModeCard(SolverModeState state, bool isSupported) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(solverModeProvider.notifier);
    return SectionCard(
      title: l10n.homeSolverMode,
      icon: Icons.auto_awesome,
      trailing: Switch(
        value: state.isRunning,
        onChanged: state.isBusy
            ? null
            : (on) => unawaited(on ? notifier.start() : notifier.stop()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isSupported
                ? l10n.homeSolverModeDesc
                : l10n.homeSolverModeUnsupported,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (state.isBusy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: state.isBusy || state.isRunning
                      ? null
                      : notifier.start,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.actionStart),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.isBusy || !state.isRunning
                      ? null
                      : notifier.stop,
                  icon: const Icon(Icons.stop),
                  label: Text(l10n.actionStop),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// iOS replacement for the Solver Mode card: explains the share-in flow (the
  /// user screenshots their game in another app and shares it here). The actual
  /// pick-a-photo button lives in the test card below; share-ins arrive via the
  /// native Share Extension and are handled by [_shareSub].
  Widget _buildShareHintCard() {
    final l10n = AppLocalizations.of(context);
    return SectionCard(
      title: l10n.homeShareInTitle,
      icon: Icons.ios_share,
      child: Text(
        l10n.homeShareInDesc,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  Widget _buildBackendCard(AppSettings settings) {
    final l10n = AppLocalizations.of(context);
    return SectionCard(
      title: l10n.backendTitle,
      icon: Icons.cloud_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
    );
  }

  Widget _buildSideCard(AppSettings settings) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(settingsProvider.notifier);
    return SectionCard(
      title: l10n.homeYourSide,
      icon: Icons.flag_outlined,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              l10n.homeYourSideDesc,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 12),
          SideSelector(
            value: settings.mySide,
            onChanged: (side) =>
                notifier.patch((s) => s.copyWith(mySide: side)),
          ),
        ],
      ),
    );
  }

  Widget _buildProvidersCard(AppSettings settings) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(settingsProvider.notifier);
    return SectionCard(
      title: l10n.providersTitle,
      icon: Icons.tune,
      child: Column(
        children: [
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
    );
  }

  Widget _buildMockTestCard(bool isAnalyzing) {
    final l10n = AppLocalizations.of(context);
    return SectionCard(
      title: l10n.homeTryMockTitle,
      icon: Icons.image_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.homeTryMockDesc,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: isAnalyzing ? null : _pickAndAnalyze,
            icon: isAnalyzing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_library_outlined),
            label: Text(
              isAnalyzing ? l10n.statusAnalyzing : l10n.homePickImage,
            ),
          ),
        ],
      ),
    );
  }
}
