import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../solver/domain/solver_enums.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildBackendCard(),
            const SizedBox(height: 16),
            _buildEngineModeCard(settings),
            const SizedBox(height: 16),
            _buildSideCard(settings),
            const SizedBox(height: 16),
            _buildProvidersCard(settings),
            const SizedBox(height: 16),
            _buildApiKeyExplanation(context),
            const SizedBox(height: 16),
            _buildEngineCard(settings),
            const SizedBox(height: 16),
            _buildCaptureAreaCard(),
            _buildLanguageCard(settings),
            const SizedBox(height: 16),
            _buildPrivacyCard(settings),
          ],
        ),
      ),
    );
  }

  Widget _buildEngineModeCard(AppSettings settings) {
    final onDevice = settings.engineMode == EngineMode.onDevice;
    return SectionCard(
      title: 'Engine mode',
      icon: Icons.dns_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<EngineMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: EngineMode.cloud,
                label: Text('Cloud'),
                icon: Icon(Icons.cloud_outlined),
              ),
              ButtonSegment(
                value: EngineMode.onDevice,
                label: Text('On-device'),
                icon: Icon(Icons.smartphone),
              ),
            ],
            selected: {settings.engineMode},
            onSelectionChanged: (s) =>
                _notifier.patch((st) => st.copyWith(engineMode: s.first)),
          ),
          const SizedBox(height: 8),
          Text(
            onDevice
                ? 'Experimental Offline mode: recognizes the board on this '
                      'device using your own OpenAI key — no backend. The local '
                      'engine isn’t bundled yet, so it shows the board but can’t '
                      'compute the move.'
                : 'Analysis runs on the backend; provider API keys stay '
                      'server-side.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (onDevice) ...[
            const SizedBox(height: 12),
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
                  icon: Icon(
                    _apiKeyObscured ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () =>
                      setState(() => _apiKeyObscured = !_apiKeyObscured),
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
              'Stored only on this device (secure storage); never sent to our '
              'backend. You pay your own API usage.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _visionModelController,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Vision model',
                hintText: 'gpt-4o',
                prefixIcon: Icon(Icons.visibility_outlined),
                helperMaxLines: 3,
                helperText:
                    'Reads the board from your screenshot. Use a capable model — '
                    'ideally the same one your Cloud mode uses. Avoid gpt-4o-mini: '
                    'it misreads pieces and produces illegal boards.',
              ),
              onChanged: (v) =>
                  _notifier.patch((s) => s.copyWith(onDeviceVisionModel: v.trim())),
            ),
          ],
        ],
      ),
    );
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

  Widget _buildApiKeyExplanation(BuildContext context) {
    return SectionCard(
      title: 'API keys',
      icon: Icons.key_outlined,
      child: Text(
        'Provider API keys are configured ON THE BACKEND and are never stored '
        'in this app. Set them as environment variables where the backend '
        'runs. This keeps secrets off the device and out of app traffic.',
        style: Theme.of(context).textTheme.bodyMedium,
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
            'Threads & Hash speed up Pikafish (ignored by the mock engine). '
            'MultiPV ranks its best moves. Pikafish has no skill level — lower '
            'the depth/time to make it play faster, not weaker.',
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
      child: SwitchListTile(
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
    );
  }
}
