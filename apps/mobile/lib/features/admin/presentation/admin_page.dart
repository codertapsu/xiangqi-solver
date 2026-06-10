import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../../../app/router.dart';
import '../../solver/presentation/providers/solver_providers.dart'
    show secureKeyStoreProvider;
import '../../solver/presentation/widgets/section_card.dart';
import '../data/admin_api.dart';
import 'admin_providers.dart';

/// Admin home: unlocks with the shared secret (stored in secure storage, then
/// verified against the backend), then offers the management sub-pages. Reached
/// only when [adminStatusProvider] reports this device is an admin.
class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage> {
  final TextEditingController _secret = TextEditingController();
  bool _unlocked = false;
  bool _busy = true;
  String? _error;
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    unawaited(_tryStoredSecret());
  }

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  /// If a secret is already stored, verify it silently so we land on the menu.
  Future<void> _tryStoredSecret() async {
    final stored = await ref.read(secureKeyStoreProvider).readAdminSecret();
    if (stored == null || stored.isEmpty) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    await _verify();
  }

  Future<void> _submit() async {
    await ref.read(secureKeyStoreProvider).writeAdminSecret(_secret.text);
    await _verify();
  }

  /// Verify the stored secret by making one guarded call.
  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(adminApiProvider).getConfig(); // 403 if the secret is wrong
      if (!mounted) return;
      setState(() {
        _unlocked = true;
        _busy = false;
      });
    } on AdminException catch (e) {
      await ref.read(secureKeyStoreProvider).clearAdminSecret();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() {
        _busy = false;
        _error = e.isForbidden ? l10n.adminWrongSecret : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppLocalizations.of(context).adminLoadFailed('$e');
      });
    }
  }

  Future<void> _lock() async {
    await ref.read(secureKeyStoreProvider).clearAdminSecret();
    if (!mounted) return;
    setState(() {
      _unlocked = false;
      _secret.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminTitle),
        actions: [
          if (_unlocked)
            IconButton(
              tooltip: l10n.adminLock,
              icon: const Icon(Icons.lock_outline),
              onPressed: _lock,
            ),
        ],
      ),
      body: SafeArea(
        child: _busy
            ? const Center(child: CircularProgressIndicator())
            : _unlocked
            ? _menu(l10n)
            : _unlock(l10n),
      ),
    );
  }

  Widget _unlock(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: l10n.adminUnlockTitle,
          icon: Icons.admin_panel_settings_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.adminSecretHelp, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              TextField(
                controller: _secret,
                obscureText: _obscured,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: l10n.adminSecretLabel,
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscured = !_obscured),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.lock_open_outlined),
                label: Text(l10n.adminUnlock),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _menu(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _tile(
          icon: Icons.tune,
          title: l10n.adminMenuConfig,
          subtitle: l10n.adminMenuConfigDesc,
          route: AppRoutes.adminConfig,
        ),
        const SizedBox(height: 12),
        _tile(
          icon: Icons.card_giftcard_outlined,
          title: l10n.adminMenuGrants,
          subtitle: l10n.adminMenuGrantsDesc,
          route: AppRoutes.adminGrants,
        ),
        const SizedBox(height: 12),
        _tile(
          icon: Icons.list_alt_outlined,
          title: l10n.adminMenuInstalls,
          subtitle: l10n.adminMenuInstallsDesc,
          route: AppRoutes.adminInstalls,
        ),
      ],
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String route,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(route),
      ),
    );
  }
}
