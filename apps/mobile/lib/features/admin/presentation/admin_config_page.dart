import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../../solver/presentation/widgets/section_card.dart';
import 'admin_providers.dart';

/// Admin editor for the server-driven remote config (`/api/config`). Loads the
/// effective `features` map, renders a typed control per field, and saves it as
/// an override. Edits a raw map (not the typed RemoteConfig) so it round-trips
/// every field the server exposes — even ones this app build doesn't model.
class AdminConfigPage extends ConsumerStatefulWidget {
  const AdminConfigPage({super.key});

  @override
  ConsumerState<AdminConfigPage> createState() => _AdminConfigPageState();
}

class _AdminConfigPageState extends ConsumerState<AdminConfigPage> {
  static const List<String> _groupOrder = [
    'ads',
    'hints',
    'onDevice',
    'history',
    'ui',
    'appIcon',
  ];

  Map<String, dynamic>? _features;
  bool _overridden = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cfg = await ref.read(adminApiProvider).getConfig();
      final features = <String, dynamic>{};
      cfg.features.forEach((group, fields) {
        features[group] = fields is Map ? Map<String, dynamic>.from(fields.cast<String, dynamic>()) : fields;
      });
      for (final c in _controllers.values) {
        c.dispose();
      }
      _controllers.clear();
      features.forEach((group, fields) {
        if (fields is Map) {
          fields.forEach((key, value) {
            if ((value is String && !(group == 'appIcon' && key == 'variant')) || value is num) {
              _controllers['$group.$key'] = TextEditingController(text: '$value');
            }
          });
        }
      });
      if (!mounted) return;
      setState(() {
        _features = features;
        _overridden = cfg.overridden;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context).adminLoadFailed('$e');
      });
    }
  }

  /// Pull controller text back into the editable map (parsing numbers).
  void _syncControllers() {
    _features?.forEach((group, fields) {
      if (fields is Map) {
        fields.forEach((key, value) {
          final c = _controllers['$group.$key'];
          if (c == null) return;
          if (value is num) {
            final n = int.tryParse(c.text.trim());
            if (n != null) fields[key] = n;
          } else if (value is String) {
            fields[key] = c.text.trim();
          }
        });
      }
    });
  }

  Future<void> _save() async {
    _syncControllers();
    setState(() {
      _saving = true;
      _error = null;
    });
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(adminApiProvider).setConfig(_features!);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _overridden = true;
      });
      _snack(l10n.adminConfigSaved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('$e');
    }
  }

  Future<void> _reset() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.adminConfigReset),
        content: Text(l10n.adminConfigResetConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.adminConfigReset),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await ref.read(adminApiProvider).resetConfig();
      await _load();
      if (mounted) _snack(l10n.adminConfigResetDone);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('$e');
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final features = _features;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminConfigTitle),
        actions: [
          if (features != null && !_saving)
            TextButton(
              onPressed: _reset,
              child: Text(l10n.adminConfigReset),
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : features == null
            ? Center(child: Text(_error ?? l10n.adminLoadFailed('')))
            : Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      _statusBanner(l10n),
                      const SizedBox(height: 12),
                      for (final group in _orderedGroups(features))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _groupCard(
                            l10n,
                            group,
                            features[group] as Map<String, dynamic>,
                          ),
                        ),
                    ],
                  ),
                  if (_saving) const LinearProgressIndicator(),
                ],
              ),
      ),
      floatingActionButton: features == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(l10n.adminConfigSave),
            ),
    );
  }

  List<String> _orderedGroups(Map<String, dynamic> features) {
    final known = _groupOrder.where(features.containsKey);
    final extra = features.keys.where((k) => !_groupOrder.contains(k));
    return [...known, ...extra];
  }

  Widget _statusBanner(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Card(
      color: _overridden ? theme.colorScheme.tertiaryContainer : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              _overridden ? Icons.edit_note : Icons.dns_outlined,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _overridden ? l10n.adminConfigOverridden : l10n.adminConfigDefaults,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.adminConfigApplyNote,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupCard(AppLocalizations l10n, String group, Map<String, dynamic> fields) {
    return SectionCard(
      title: _groupLabel(l10n, group),
      icon: _groupIcon(group),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final key in fields.keys) _field(l10n, group, key, fields[key]),
        ],
      ),
    );
  }

  Widget _field(AppLocalizations l10n, String group, String key, dynamic value) {
    final label = _fieldLabel(l10n, group, key);
    if (value is bool) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(label),
        value: value,
        onChanged: (v) => setState(() => (_features![group] as Map)[key] = v),
      );
    }
    if (group == 'appIcon' && key == 'variant') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            DropdownButton<String>(
              value: ['auto', 'vi', 'en'].contains(value) ? value as String : 'auto',
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('auto')),
                DropdownMenuItem(value: 'vi', child: Text('vi')),
                DropdownMenuItem(value: 'en', child: Text('en')),
              ],
              onChanged: (v) => setState(() => (_features![group] as Map)[key] = v),
            ),
          ],
        ),
      );
    }
    // String / number → text field (controller kept in _controllers).
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: _controllers['$group.$key'],
        keyboardType: value is num ? const TextInputType.numberWithOptions(decimal: false) : TextInputType.text,
        inputFormatters: value is num ? [FilteringTextInputFormatter.digitsOnly] : null,
        autocorrect: false,
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }

  IconData _groupIcon(String group) => switch (group) {
    'ads' => Icons.ads_click_outlined,
    'hints' => Icons.toll_outlined,
    'onDevice' => Icons.smartphone_outlined,
    'history' => Icons.history,
    'ui' => Icons.visibility_outlined,
    'appIcon' => Icons.apps_outlined,
    _ => Icons.settings_outlined,
  };

  String _groupLabel(AppLocalizations l10n, String group) => switch (group) {
    'ads' => l10n.adminCfgGroupAds,
    'hints' => l10n.adminCfgGroupHints,
    'onDevice' => l10n.adminCfgGroupOnDevice,
    'history' => l10n.adminCfgGroupHistory,
    'ui' => l10n.adminCfgGroupUi,
    'appIcon' => l10n.adminCfgGroupAppIcon,
    _ => group,
  };

  String _fieldLabel(AppLocalizations l10n, String group, String key) => switch ('$group.$key') {
    'ads.rewarded' => l10n.adminCfgRewarded,
    'ads.banner' => l10n.adminCfgBanner,
    'ads.appOpen' => l10n.adminCfgAppOpen,
    'ads.useReal' => l10n.adminCfgUseReal,
    'hints.freeOnInstall' => l10n.adminCfgFreeOnInstall,
    'hints.ownKeyDivisor' => l10n.adminCfgOwnKeyDivisor,
    'onDevice.enabled' => l10n.adminCfgOnDeviceEnabled,
    'onDevice.netUrl' => l10n.adminCfgNetUrl,
    'onDevice.netBytes' => l10n.adminCfgNetBytes,
    'onDevice.visionModel' => l10n.adminCfgVisionModel,
    'history.storedScreenshotsMax' => l10n.adminCfgStoredScreenshots,
    'ui.backend' => l10n.adminCfgUiBackend,
    'ui.providers' => l10n.adminCfgUiProviders,
    'ui.engineTuning' => l10n.adminCfgUiEngineTuning,
    'ui.visionModel' => l10n.adminCfgUiVisionModel,
    'ui.licenses' => l10n.adminCfgUiLicenses,
    'ui.deviceId' => l10n.adminCfgUiDeviceId,
    'appIcon.variant' => l10n.adminCfgIconVariant,
    _ => '$group.$key',
  };
}
