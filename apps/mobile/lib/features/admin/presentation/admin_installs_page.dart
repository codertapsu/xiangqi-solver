import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import 'admin_providers.dart';

/// Admin manager for `installs.json` — the device install ledger that stops a
/// reinstall from re-granting the free starter hints. View / add / edit / remove.
class AdminInstallsPage extends ConsumerStatefulWidget {
  const AdminInstallsPage({super.key});

  @override
  ConsumerState<AdminInstallsPage> createState() => _AdminInstallsPageState();
}

class _AdminInstallsPageState extends ConsumerState<AdminInstallsPage> {
  Map<String, String>? _installs;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final installs = await ref.read(adminApiProvider).getInstalls();
      if (!mounted) return;
      setState(() {
        _installs = installs;
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

  Future<void> _edit({String? deviceId}) async {
    final l10n = AppLocalizations.of(context);
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => _InstallDialog(deviceId: deviceId),
    );
    if (id == null) return;
    try {
      await ref.read(adminApiProvider).setInstall(id);
      await _load();
      if (mounted) _snack(l10n.adminInstallSaved);
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Future<void> _remove(String deviceId) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.adminRemove),
        content: Text(l10n.adminRemoveConfirm(deviceId)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.adminRemove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(adminApiProvider).removeInstall(deviceId);
      await _load();
      if (mounted) _snack(l10n.adminInstallRemoved);
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _fmt(String iso) {
    final dt = DateTime.tryParse(iso);
    return dt == null ? iso : DateFormat.yMMMd().add_Hm().format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final installs = _installs;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminMenuInstalls),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: l10n.actionRetry,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(l10n.adminAdd),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : installs == null
            ? Center(child: Text(_error ?? l10n.adminLoadFailed('')))
            : installs.isEmpty
            ? Center(child: Text(l10n.adminInstallsEmpty))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: installs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final e = installs.entries.elementAt(index);
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.smartphone_outlined),
                      title: Text(
                        e.key,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('${l10n.adminInstallFirstSeen}: ${_fmt(e.value)}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _remove(e.key),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _InstallDialog extends StatefulWidget {
  const _InstallDialog({this.deviceId});
  final String? deviceId;

  @override
  State<_InstallDialog> createState() => _InstallDialogState();
}

class _InstallDialogState extends State<_InstallDialog> {
  late final TextEditingController _id = TextEditingController(
    text: widget.deviceId ?? '',
  );

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminAddInstall),
      content: TextField(
        controller: _id,
        autocorrect: false,
        decoration: InputDecoration(labelText: l10n.adminDeviceId),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () {
            final id = _id.text.trim();
            if (id.length < 8) return;
            Navigator.pop(context, id);
          },
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }
}
