import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../settings/data/settings_repository.dart';
import '../../data/analysis_api.dart';
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
  String? _healthLine;
  bool _testingConnection = false;

  @override
  void initState() {
    super.initState();
    _backendController.text = ref.read(settingsProvider).backendUrl;
    // Bridge native "analyze this screenshot" requests to upload + navigate.
    _analyzeSub = ref
        .read(solverModeProvider.notifier)
        .analyzeRequests
        .listen(_handleAnalyzeRequest);
  }

  @override
  void dispose() {
    _backendController.dispose();
    unawaited(_analyzeSub?.cancel());
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
    setState(() {
      _testingConnection = false;
      _healthLine = result.when(
        success: (HealthStatus h) =>
            'OK • v${h.version} • ${h.latency.inMilliseconds} ms '
            '• uptime ${h.uptimeSeconds.toStringAsFixed(0)}s',
        failure: (f) => 'Error: ${f.message}',
      );
    });
  }

  Future<void> _pickAndAnalyze() async {
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
      );
    } catch (e) {
      _snack('Could not open image picker: $e');
      return;
    }
    if (picked == null) return;
    await ref
        .read(analysisProvider.notifier)
        .analyzeScreenshot(File(picked.path));
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
    final settings = ref.watch(settingsProvider);
    final solverMode = ref.watch(solverModeProvider);
    final analysisStatus = ref.watch(analysisProvider);
    final native = ref.watch(nativeSolverProvider);

    // Surface transient solver-mode messages as snackbars.
    ref.listen(solverModeProvider, (prev, next) {
      final message = next.message;
      if (message != null && message != prev?.message) {
        _snack(message);
        ref.read(solverModeProvider.notifier).clearMessage();
      }
    });

    final isAnalyzing = analysisStatus is AnalysisLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history),
            onPressed: () => context.push(AppRoutes.history),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const PrivacyBanner(),
            const SizedBox(height: 16),
            _buildSolverModeCard(solverMode, native.isSupported),
            const SizedBox(height: 16),
            _buildBackendCard(settings),
            const SizedBox(height: 16),
            _buildProvidersCard(settings),
            const SizedBox(height: 16),
            _buildSideCard(settings),
            const SizedBox(height: 16),
            _buildMockTestCard(isAnalyzing),
          ],
        ),
      ),
    );
  }

  Widget _buildSolverModeCard(SolverModeState state, bool isSupported) {
    final notifier = ref.read(solverModeProvider.notifier);
    return SectionCard(
      title: 'Solver Mode',
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
                ? 'Starts a floating overlay and screen capture so you can '
                      'analyze the board in any app.'
                : 'Solver mode needs a physical Android device. The rest of '
                      'the app still works for testing.',
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
                  label: const Text('Start'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.isBusy || !state.isRunning
                      ? null
                      : notifier.stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackendCard(AppSettings settings) {
    return SectionCard(
      title: 'Backend',
      icon: Icons.cloud_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _backendController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Backend URL',
              hintText: 'http://10.0.2.2:3000',
              prefixIcon: Icon(Icons.link),
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
                  label: const Text('Test Backend Connection'),
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
                  _snack('Backend URL saved.');
                },
                child: const Text('Save'),
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
    final notifier = ref.read(settingsProvider.notifier);
    return SectionCard(
      title: 'Your side',
      icon: Icons.flag_outlined,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              'Whose move it is when you solve.',
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
    final notifier = ref.read(settingsProvider.notifier);
    return SectionCard(
      title: 'Providers',
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
    return SectionCard(
      title: 'Try it (mock test)',
      icon: Icons.image_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick an image to exercise the full upload + analysis pipeline '
            'without native screen capture.',
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
              isAnalyzing ? 'Analyzing…' : 'Pick image & analyze (mock test)',
            ),
          ),
        ],
      ),
    );
  }
}
