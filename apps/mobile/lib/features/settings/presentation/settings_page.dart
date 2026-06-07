import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/remote_config/remote_config_provider.dart';
import '../../monetization/presentation/banner_ad.dart';
import '../../solver/domain/solver_enums.dart';
import '../../solver/presentation/providers/engine_net_provider.dart';
import '../../solver/presentation/providers/solver_providers.dart';
import '../../solver/presentation/widgets/provider_dropdowns.dart';
import '../../solver/presentation/widgets/section_card.dart';
import '../../solver/presentation/widgets/side_selector.dart';
import '../data/settings_repository.dart';

/// Full settings editor: backend URL, providers, engine tuning, language, and
/// local screenshot storage. API keys are intentionally NOT here — they live on
/// the backend only.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _backendController;
  late final TextEditingController _visionModelController;
  final TextEditingController _apiKeyController = TextEditingController();
  bool _apiKeyObscured = true;

  @override
  void initState() {
    super.initState();
    _backendController = TextEditingController(
      text: ref.read(settingsProvider).backendUrl,
    );
    _visionModelController = TextEditingController(
      text: ref.read(settingsProvider).onDeviceVisionModel,
    );
    // Load any previously stored BYO key into the field (on-device mode).
    ref.read(secureKeyStoreProvider).readOpenAiKey().then((key) {
      if (mounted && key != null) _apiKeyController.text = key;
    });
  }

  @override
  void dispose() {
    _backendController.dispose();
    _visionModelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  SettingsNotifier get _notifier => ref.read(settingsProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final remoteConfig = ref.watch(remoteConfigProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const BannerAdWidget(),
            if (remoteConfig.showBackendSection) ...[
              _buildBackendCard(),
              const SizedBox(height: 16),
            ],
            _buildModeCard(settings),
            const SizedBox(height: 16),
            _buildSideCard(settings),
            const SizedBox(height: 16),
            if (remoteConfig.showProvidersSection) ...[
              _buildProvidersCard(settings),
              const SizedBox(height: 16),
            ],
            if (remoteConfig.showEngineTuning) ...[
              _buildEngineCard(settings),
              const SizedBox(height: 16),
            ],
            _buildCaptureAreaCard(),
            _buildLanguageCard(settings),
            const SizedBox(height: 16),
            _buildPrivacyCard(settings),
          ],
        ),
      ),
    );
  }

  /// Two INDEPENDENT choices: who reads the board (AI key) and where the engine
  /// runs. Shows the hint cost, on-device download status, and (for the own-key
  /// option) the API-key + vision-model fields.
  Widget _buildModeCard(AppSettings settings) {
    final theme = Theme.of(context);
    final netState = ref.watch(engineNetProvider);
    final onDeviceUnavailable =
        netState is EngineNetUnsupported || netState is EngineNetFailed;

    // If on-device became unusable (download failed / unsupported here) while it
    // was the selected engine, fall back to Cloud so the user is never stuck on a
    // disabled, non-runnable segment. Done post-frame to avoid mutating during build.
    if (onDeviceUnavailable && settings.engineLocation == EngineLocation.onDevice) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(settingsProvider).engineLocation != EngineLocation.onDevice) return;
        _notifier.patch((s) => s.copyWith(engineLocation: EngineLocation.cloud));
        _snack('On-device engine unavailable — switched the engine to Cloud.');
      });
    }

    return SectionCard(
      title: 'Analysis mode',
      icon: Icons.dns_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Board reading (AI key)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<AiKeySource>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: AiKeySource.ours,
                label: Text('Our key'),
                icon: Icon(Icons.cloud_outlined),
              ),
              ButtonSegment(
                value: AiKeySource.own,
                label: Text('My key'),
                icon: Icon(Icons.key_outlined),
              ),
            ],
            selected: {settings.aiKeySource},
            onSelectionChanged: (s) => _onAiKeySelected(s.first),
          ),
          const SizedBox(height: 4),
          Text(
            settings.aiKeySource == AiKeySource.own
                ? 'Your own OpenAI key reads the board on this device — usually '
                      'cheaper, and your key never leaves your phone.'
                : 'We read the board for you using our OpenAI key.',
            style: theme.textTheme.bodySmall,
          ),

          // The API-key field appears right here, so picking "My key" immediately
          // reveals where to enter it.
          if (settings.aiKeySource == AiKeySource.own) ...[
            const Divider(height: 28),
            _buildOwnKeyFields(
              theme,
              showVisionModel: ref.watch(remoteConfigProvider).showVisionModel,
            ),
          ],

          const SizedBox(height: 16),
          Text('Best move (engine)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<EngineLocation>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(
                value: EngineLocation.cloud,
                label: Text('Cloud'),
                icon: Icon(Icons.cloud_outlined),
              ),
              ButtonSegment(
                value: EngineLocation.onDevice,
                label: const Text('On-device'),
                icon: const Icon(Icons.smartphone_outlined),
                enabled: !onDeviceUnavailable,
              ),
            ],
            selected: {settings.engineLocation},
            onSelectionChanged: (s) => _onEngineSelected(s.first),
          ),
          const SizedBox(height: 4),
          Text(
            settings.engineLocation == EngineLocation.onDevice
                ? 'On-device engine is faster, but its move may be weaker or less '
                      'accurate than our cloud engine.'
                : 'Our cloud engine computes the best move.',
            style: theme.textTheme.bodySmall,
          ),

          _buildEngineNetStatus(netState),

          const SizedBox(height: 12),
          _buildCostHint(settings, theme),
        ],
      ),
    );
  }

  /// Download progress / ready / failed status for the on-device engine net.
  Widget _buildEngineNetStatus(EngineNetState state) {
    final theme = Theme.of(context);
    switch (state) {
      case EngineNetDownloading(:final progress):
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    progress == null
                        ? 'Downloading on-device engine…'
                        : 'Downloading on-device engine ${(progress * 100).round()}%',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: progress),
            ],
          ),
        );
      case EngineNetReady():
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text('On-device engine ready.', style: theme.textTheme.bodySmall),
            ],
          ),
        );
      case EngineNetFailed(:final message):
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => ref.read(engineNetProvider.notifier).retry(),
                  child: const Text('Retry download'),
                ),
              ),
            ],
          ),
        );
      case EngineNetUnsupported():
      case EngineNetIdle():
        return const SizedBox.shrink();
    }
  }

  /// One-line summary of what the current mode costs in hints.
  Widget _buildCostHint(AppSettings settings, ThemeData theme) {
    final String text;
    if (settings.isFullyLocal) {
      final n = ref.watch(remoteConfigProvider).ownKeyHintDivisor;
      text =
          'Runs on your device — no hints used, unless the on-device engine '
          'can\'t solve and we finish on our cloud (1 hint per $n).';
    } else if (settings.aiKeySource == AiKeySource.ours) {
      text = 'Uses our key — 1 hint per analysis.';
    } else {
      final n = ref.watch(remoteConfigProvider).ownKeyHintDivisor;
      text = 'Your key + our cloud engine — 1 hint per $n analyses.';
    }
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  /// The personal OpenAI key field (always, when AI key = own) plus the optional
  /// vision-model field (shown only when [showVisionModel] is enabled remotely).
  Widget _buildOwnKeyFields(ThemeData theme, {required bool showVisionModel}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _apiKeyController,
          obscureText: _apiKeyObscured,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Your OpenAI API key',
            hintText: 'sk-…',
            prefixIcon: const Icon(Icons.key_outlined),
            suffixIcon: IconButton(
              tooltip: _apiKeyObscured ? 'Show' : 'Hide',
              icon: Icon(_apiKeyObscured ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _apiKeyObscured = !_apiKeyObscured),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _saveApiKey,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save key'),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(onPressed: _clearApiKey, child: const Text('Clear')),
          ],
        ),
        Text(
          'Stored only on this device (secure storage); never sent to our backend.',
          style: theme.textTheme.bodySmall,
        ),
        if (showVisionModel) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _visionModelController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Vision model',
              hintText: 'gpt-5.4',
              prefixIcon: Icon(Icons.visibility_outlined),
              helperMaxLines: 3,
              helperText:
                  'Reads the board from your screenshot. Use a capable model. Avoid '
                  'gpt-4o-mini: it misreads pieces and produces illegal boards.',
            ),
            onChanged: (v) => _notifier.patch((s) => s.copyWith(onDeviceVisionModel: v.trim())),
          ),
        ],
      ],
    );
  }

  Future<void> _onAiKeySelected(AiKeySource source) async {
    await _notifier.patch((s) => s.copyWith(aiKeySource: source));
    await _recheckMode();
  }

  Future<void> _onEngineSelected(EngineLocation location) async {
    if (location == EngineLocation.onDevice) {
      unawaited(ref.read(engineNetProvider.notifier).ensureDownloaded());
    }
    await _notifier.patch((s) => s.copyWith(engineLocation: location));
    await _recheckMode();
  }

  /// Re-checks that the chosen combo can run; falls back to fully-local (or
  /// warns) when the backend is needed but unreachable.
  Future<void> _recheckMode() async {
    final outcome = await ref.read(modeCoordinatorProvider).ensureUsableMode();
    if (!mounted) return;
    switch (outcome) {
      case ModeCheckOutcome.ready:
        break;
      case ModeCheckOutcome.switchedToOnDevice:
        _snack('Server unavailable — switched to your own key + on-device engine.');
      case ModeCheckOutcome.noModeAvailable:
        _snack('Server unavailable. Add your own OpenAI key to analyze on-device.');
    }
  }

  Future<void> _saveApiKey() async {
    await ref.read(secureKeyStoreProvider).writeOpenAiKey(_apiKeyController.text);
    _snack('API key saved on this device.');
  }

  Future<void> _clearApiKey() async {
    await ref.read(secureKeyStoreProvider).clearOpenAiKey();
    _apiKeyController.clear();
    _snack('API key cleared.');
  }

  Widget _buildBackendCard() {
    return SectionCard(
      title: 'Backend',
      icon: Icons.cloud_outlined,
      child: TextField(
        controller: _backendController,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Base URL',
          hintText: 'http://10.0.2.2:3000',
          prefixIcon: Icon(Icons.link),
        ),
        onChanged: (value) =>
            _notifier.patch((s) => s.copyWith(backendUrl: value.trim())),
      ),
    );
  }

  Widget _buildSideCard(AppSettings settings) {
    return SectionCard(
      title: 'Your side',
      icon: Icons.flag_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick the side you are playing. The backend treats this as the side '
            'to move, so the engine always solves for your turn.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          SideSelector(
            value: settings.mySide,
            onChanged: (side) =>
                _notifier.patch((s) => s.copyWith(mySide: side)),
          ),
        ],
      ),
    );
  }

  Widget _buildProvidersCard(AppSettings settings) {
    return SectionCard(
      title: 'Providers',
      icon: Icons.tune,
      child: Column(
        children: [
          AiProviderDropdown(
            value: settings.aiProvider,
            onChanged: (v) => _notifier.patch((s) => s.copyWith(aiProvider: v)),
          ),
          const SizedBox(height: 12),
          EngineProviderDropdown(
            value: settings.engineProvider,
            onChanged: (v) =>
                _notifier.patch((s) => s.copyWith(engineProvider: v)),
          ),
        ],
      ),
    );
  }

  Widget _buildEngineCard(AppSettings settings) {
    return SectionCard(
      title: 'Engine tuning',
      icon: Icons.memory_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Search depth: ${settings.engineDepth}'),
          Slider(
            value: settings.engineDepth.toDouble(),
            min: 1,
            max: 30,
            divisions: 29,
            label: '${settings.engineDepth}',
            onChanged: (v) =>
                _notifier.patch((s) => s.copyWith(engineDepth: v.round())),
          ),
          const SizedBox(height: 8),
          Text('Move time: ${settings.engineMoveTimeMs} ms'),
          Slider(
            value: settings.engineMoveTimeMs
                .toDouble()
                .clamp(50, 60000),
            min: 50,
            max: 60000,
            divisions: 120,
            label: '${settings.engineMoveTimeMs} ms',
            onChanged: (v) => _notifier
                .patch((s) => s.copyWith(engineMoveTimeMs: v.round())),
          ),
          const SizedBox(height: 8),
          Text('Top moves to show: ${settings.engineMultiPv}'),
          Slider(
            value: settings.engineMultiPv.toDouble().clamp(1, 5),
            min: 1,
            max: 5,
            divisions: 4,
            label: '${settings.engineMultiPv}',
            onChanged: (v) =>
                _notifier.patch((s) => s.copyWith(engineMultiPv: v.round())),
          ),
          const SizedBox(height: 8),
          Text('Threads: ${settings.engineThreads}'),
          Slider(
            value: settings.engineThreads.toDouble().clamp(1, 8),
            min: 1,
            max: 8,
            divisions: 7,
            label: '${settings.engineThreads}',
            onChanged: (v) =>
                _notifier.patch((s) => s.copyWith(engineThreads: v.round())),
          ),
          const SizedBox(height: 8),
          Text('Hash: ${settings.engineHashMb} MB'),
          Slider(
            value: settings.engineHashMb.toDouble().clamp(16, 1024),
            min: 16,
            max: 1024,
            divisions: 63,
            label: '${settings.engineHashMb} MB',
            onChanged: (v) =>
                _notifier.patch((s) => s.copyWith(engineHashMb: v.round())),
          ),
          Text(
            'Threads & Hash make the engine faster. "Top moves" shows several of '
            'its best options. For a quicker answer, lower the search depth or '
            'move time — this won\'t make it play weaker.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  /// Android-only: manage the optional screen capture focus area. Selecting an
  /// area is driven by the floating overlay (it needs Solver Mode running), but
  /// resetting to full screen works any time.
  Widget _buildCaptureAreaCard() {
    final native = ref.read(nativeSolverProvider);
    if (!native.isSupported) return const SizedBox.shrink();
    return Column(
      children: [
        SectionCard(
          title: 'Capture area',
          icon: Icons.crop_free,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'By default the whole screen is captured. In Solver Mode you can '
                'draw a focus box (e.g. just the board) from the floating '
                'widget’s “Select capture area”, or start it here.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectCaptureArea,
                      icon: const Icon(Icons.crop),
                      label: const Text('Select area'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _resetCaptureArea,
                      icon: const Icon(Icons.fullscreen),
                      label: const Text('Use full screen'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _selectCaptureArea() async {
    try {
      await ref.read(nativeSolverProvider).startRegionSelection();
    } catch (_) {
      _snack('Start Solver Mode first, then select the capture area.');
    }
  }

  Future<void> _resetCaptureArea() async {
    await ref.read(nativeSolverProvider).clearCaptureRegion();
    _snack('Capture area reset to full screen.');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildLanguageCard(AppSettings settings) {
    return SectionCard(
      title: 'Language',
      icon: Icons.language_outlined,
      child: DropdownButtonFormField<String>(
        initialValue: settings.language,
        decoration: const InputDecoration(
          labelText: 'Move-notation language',
        ),
        items: const [
          DropdownMenuItem(value: 'en', child: Text('English')),
          DropdownMenuItem(value: 'vi', child: Text('Tiếng Việt')),
          DropdownMenuItem(value: 'zh', child: Text('中文')),
        ],
        onChanged: (v) {
          if (v != null) _notifier.patch((s) => s.copyWith(language: v));
        },
      ),
    );
  }

  Widget _buildPrivacyCard(AppSettings settings) {
    return SectionCard(
      title: 'Privacy',
      icon: Icons.privacy_tip_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.storeScreenshots,
            title: const Text('Store screenshots locally'),
            subtitle: const Text(
              'Off by default. When on, analyzed images are kept on this device '
              'and shown in history.',
            ),
            onChanged: (v) =>
                _notifier.patch((s) => s.copyWith(storeScreenshots: v)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.policy_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: _openPrivacyPolicy,
          ),
          if (ref.watch(remoteConfigProvider).showLicenses)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: const Text('Open-source licenses'),
              // subtitle: const Text('Incl. the GPLv3 Pikafish on-device engine'),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => showLicensePage(
                context: context,
                applicationName: AppConstants.appName,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(AppConstants.privacyPolicyUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Could not open the privacy policy.')),
        );
    }
  }
}
