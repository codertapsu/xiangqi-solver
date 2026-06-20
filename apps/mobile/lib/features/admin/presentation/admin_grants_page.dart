import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import 'admin_providers.dart';

/// Admin manager for `grants.json` — the manual per-device starting hint
/// balances. View / add / edit / remove entries.
class AdminGrantsPage extends ConsumerStatefulWidget {
  const AdminGrantsPage({super.key});

  @override
  ConsumerState<AdminGrantsPage> createState() => _AdminGrantsPageState();
}

class _AdminGrantsPageState extends ConsumerState<AdminGrantsPage> {
  Map<String, int>? _grants;
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
      final grants = await ref.read(adminApiProvider).getGrants();
      if (!mounted) return;
      setState(() {
        _grants = grants;
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

  Future<void> _edit({String? deviceId, int? hints}) async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<({String id, int hints})>(
      context: context,
      builder: (ctx) => _GrantDialog(deviceId: deviceId, hints: hints),
    );
    if (result == null) return;
    try {
      await ref.read(adminApiProvider).setGrant(result.id, result.hints);
      await _load();
      if (mounted) _snack(l10n.adminGrantSaved);
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
      await ref.read(adminApiProvider).removeGrant(deviceId);
      await _load();
      if (mounted) _snack(l10n.adminGrantRemoved);
    } catch (e) {
      if (mounted) _snack('$e');
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
    final grants = _grants;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminMenuGrants),
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
            : grants == null
            ? Center(child: Text(_error ?? l10n.adminLoadFailed('')))
            : grants.isEmpty
            ? Center(child: Text(l10n.adminGrantsEmpty))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: grants.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final e = grants.entries.elementAt(index);

                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.card_giftcard_outlined),
                      title: Text('${e.value}  ${l10n.adminGrantHints}'),
                      subtitle: Text(
                        e.key,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(
                              deviceId: e.key,
                              hints: e.value,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _remove(e.key),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _GrantDialog extends StatefulWidget {
  const _GrantDialog({this.deviceId, this.hints});
  final String? deviceId;
  final int? hints;

  @override
  State<_GrantDialog> createState() => _GrantDialogState();
}

class _GrantDialogState extends State<_GrantDialog> {
  late final TextEditingController _id = TextEditingController(text: widget.deviceId ?? '');
  late final TextEditingController _hints = TextEditingController(text: '${widget.hints ?? 0}');

  @override
  void dispose() {
    _id.dispose();
    _hints.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final editing = widget.deviceId != null;
    return AlertDialog(
      title: Text(editing ? l10n.adminEditGrant : l10n.adminAddGrant),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _id,
            readOnly: editing,
            autocorrect: false,
            decoration: InputDecoration(labelText: l10n.adminDeviceId),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _hints,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: l10n.adminGrantHints),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.actionCancel)),
        FilledButton(
          onPressed: () {
            final id = _id.text.trim();
            final hints = int.tryParse(_hints.text.trim()) ?? 0;
            if (id.length < 8) return;
            Navigator.pop(context, (id: id, hints: hints));
          },
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }
}
