import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

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

  AppLocalizations get _l10n => AppLocalizations.of(context);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final remoteConfig = ref.watch(remoteConfigProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_l10n.settingsTitle)),
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
    final l10n = _l10n;
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
        _snack(_l10n.settingsEngineSwitchedCloud);
      });
    }

    return SectionCard(
      title: l10n.settingsAnalysisMode,
      icon: Icons.dns_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.settingsBoardReading, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<AiKeySource>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: AiKeySource.ours,
                label: Text(l10n.settingsOurKeyShort),
                icon: const Icon(Icons.cloud_outlined),
              ),
              ButtonSegment(
                value: AiKeySource.own,
                label: Text(l10n.settingsMyKeyShort),
                icon: const Icon(Icons.key_outlined),
              ),
            ],
            selected: {settings.aiKeySource},
            onSelectionChanged: (s) => _onAiKeySelected(s.first),
          ),
          const SizedBox(height: 4),
          Text(
            settings.aiKeySource == AiKeySource.own
                ? l10n.settingsBoardReadingOwnDesc
                : l10n.settingsBoardReadingOursDesc,
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
          Text(l10n.settingsBestMoveEngine, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<EngineLocation>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: EngineLocation.cloud,
                label: Text(l10n.engineLocationCloud),
                icon: const Icon(Icons.cloud_outlined),
              ),
              ButtonSegment(
                value: EngineLocation.onDevice,
                label: Text(l10n.engineLocationOnDevice),
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
                ? l10n.settingsEngineOnDeviceDesc
                : l10n.settingsEngineCloudDesc,
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
    final l10n = _l10n;
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
                        ? l10n.settingsDownloadingEngine
                        : l10n.settingsDownloadingEnginePct((progress * 100).round()),
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
              Text(l10n.settingsEngineReady, style: theme.textTheme.bodySmall),
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
                  child: Text(l10n.settingsRetryDownload),
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
    final l10n = _l10n;
    final String text;
    if (settings.isFullyLocal) {
      final n = ref.watch(remoteConfigProvider).ownKeyHintDivisor;
      text = l10n.costHintOwnOnDevice(n);
    } else if (settings.aiKeySource == AiKeySource.ours) {
      text = l10n.costHintOurs;
    } else {
      final n = ref.watch(remoteConfigProvider).ownKeyHintDivisor;
      text = l10n.costHintOwnCloud(n);
    }
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  /// The personal OpenAI key field (always, when AI key = own) plus the optional
  /// vision-model field (shown only when [showVisionModel] is enabled remotely).
  Widget _buildOwnKeyFields(ThemeData theme, {required bool showVisionModel}) {
    final l10n = _l10n;
    final backendModel = ref.watch(remoteConfigProvider).onDeviceVisionModel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _apiKeyController,
          obscureText: _apiKeyObscured,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: l10n.settingsApiKeyLabel,
            hintText: 'sk-…',
            prefixIcon: const Icon(Icons.key_outlined),
            suffixIcon: IconButton(
              tooltip: _apiKeyObscured ? l10n.actionShow : l10n.actionHide,
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
                label: Text(l10n.settingsSaveKey),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(onPressed: _clearApiKey, child: Text(l10n.actionClear)),
          ],
        ),
        Text(
          l10n.settingsApiKeyHelp,
          style: theme.textTheme.bodySmall,
        ),
        if (showVisionModel) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _visionModelController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.settingsVisionModelLabel,
              hintText: backendModel,
              prefixIcon: const Icon(Icons.visibility_outlined),
              helperMaxLines: 3,
              helperText: l10n.settingsVisionModelHelp(backendModel),
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
        _snack(_l10n.settingsServerSwitchedOwn);
      case ModeCheckOutcome.noModeAvailable:
        _snack(_l10n.settingsServerAddKey);
    }
  }

  Future<void> _saveApiKey() async {
    await ref.read(secureKeyStoreProvider).writeOpenAiKey(_apiKeyController.text);
    _snack(_l10n.settingsApiKeySaved);
  }

  Future<void> _clearApiKey() async {
    await ref.read(secureKeyStoreProvider).clearOpenAiKey();
    _apiKeyController.clear();
    _snack(_l10n.settingsApiKeyCleared);
  }

  Widget _buildBackendCard() {
    return SectionCard(
      title: _l10n.backendTitle,
      icon: Icons.cloud_outlined,
      child: TextField(
        controller: _backendController,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: _l10n.backendBaseUrlLabel,
          hintText: 'http://10.0.2.2:3000',
          prefixIcon: const Icon(Icons.link),
        ),
        onChanged: (value) =>
            _notifier.patch((s) => s.copyWith(backendUrl: value.trim())),
      ),
    );
  }

  Widget _buildSideCard(AppSettings settings) {
    return SectionCard(
      title: _l10n.homeYourSide,
      icon: Icons.flag_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _l10n.settingsYourSideDesc,
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
      title: _l10n.providersTitle,
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
    final l10n = _l10n;
    return SectionCard(
      title: l10n.settingsEngineTuning,
      icon: Icons.memory_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsSearchDepth(settings.engineDepth)),
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
          Text(l10n.settingsMoveTime(settings.engineMoveTimeMs)),
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
          Text(l10n.settingsTopMoves(settings.engineMultiPv)),
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
          Text(l10n.settingsThreads(settings.engineThreads)),
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
          Text(l10n.settingsHash(settings.engineHashMb)),
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
            l10n.settingsEngineTuningHelp,
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
    final l10n = _l10n;
    return Column(
      children: [
        SectionCard(
          title: l10n.settingsCaptureArea,
          icon: Icons.crop_free,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.settingsCaptureAreaDesc,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectCaptureArea,
                      icon: const Icon(Icons.crop),
                      label: Text(l10n.settingsSelectArea),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _resetCaptureArea,
                      icon: const Icon(Icons.fullscreen),
                      label: Text(l10n.settingsUseFullScreen),
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
      _snack(_l10n.settingsStartSolverFirst);
    }
  }

  Future<void> _resetCaptureArea() async {
    await ref.read(nativeSolverProvider).clearCaptureRegion();
    _snack(_l10n.settingsCaptureReset);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildLanguageCard(AppSettings settings) {
    final l10n = _l10n;
    return SectionCard(
      title: l10n.settingsLanguageCard,
      icon: Icons.language_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // App UI language. Changing this re-localizes the whole app live.
          DropdownButtonFormField<String>(
            initialValue: settings.appLanguage,
            decoration: InputDecoration(
              labelText: l10n.settingsAppLanguage,
            ),
            items: [
              DropdownMenuItem(value: 'system', child: Text(l10n.languageSystem)),
              const DropdownMenuItem(value: 'vi', child: Text('Tiếng Việt')),
              const DropdownMenuItem(value: 'en', child: Text('English')),
            ],
            onChanged: (v) {
              if (v != null) _notifier.patch((s) => s.copyWith(appLanguage: v));
            },
          ),
          const SizedBox(height: 12),
          // Chess move-notation output language (independent of the UI language).
          DropdownButtonFormField<String>(
            initialValue: settings.language,
            decoration: InputDecoration(
              labelText: l10n.settingsMoveNotationLanguage,
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
        ],
      ),
    );
  }

  Widget _buildPrivacyCard(AppSettings settings) {
    final l10n = _l10n;
    return SectionCard(
      title: l10n.settingsPrivacy,
      icon: Icons.privacy_tip_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.storeScreenshots,
            title: Text(l10n.settingsStoreScreenshots),
            subtitle: Text(l10n.settingsStoreScreenshotsDesc),
            onChanged: (v) =>
                _notifier.patch((s) => s.copyWith(storeScreenshots: v)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.policy_outlined),
            title: Text(l10n.settingsPrivacyPolicy),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: _openPrivacyPolicy,
          ),
          if (ref.watch(remoteConfigProvider).showLicenses)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text(l10n.settingsLicenses),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => showLicensePage(
                context: context,
                applicationName: _l10n.appTitle,
              ),
            ),
          _buildDeviceIdTile(),
        ],
      ),
    );
  }

  /// Shows this device's stable ID (copyable) — share it with support to receive
  /// a custom hint grant on (re)install.
  Widget _buildDeviceIdTile() {
    final deviceId = ref.watch(deviceIdProvider);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.fingerprint_outlined),
      title: Text(_l10n.settingsDeviceId),
      subtitle: Text(
        deviceId,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
        ),
      ),
      trailing: const Icon(Icons.copy_outlined, size: 18),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: deviceId));
        _snack(_l10n.settingsDeviceIdCopied);
      },
    );
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(AppConstants.privacyPolicyUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(_l10n.settingsPrivacyOpenFailed)),
        );
    }
  }
}
