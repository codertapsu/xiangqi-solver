import 'package:flutter/material.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

/// Explains Solver Mode's two Android permissions before the system screens
/// ask for them. Resolves to true when the user chooses to continue.
Future<bool> showSolverPermissionsSheet(BuildContext context) async {
  final go = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const SolverPermissionsSheet(),
  );
  return go ?? false;
}

class SolverPermissionsSheet extends StatelessWidget {
  const SolverPermissionsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // useSafeArea only guards the top and sides; keep the button above the
    // gesture/navigation bar too.
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.solverPermsTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 20),
            _Permission(
              number: 1,
              icon: Icons.picture_in_picture_alt_rounded,
              title: l10n.solverPermOverlayTitle,
              body: l10n.solverPermOverlayBody,
            ),
            _Permission(
              number: 2,
              icon: Icons.screenshot_monitor_rounded,
              title: l10n.solverPermCaptureTitle,
              body: l10n.solverPermCaptureBody,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.actionContinue),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.actionNotNow),
            ),
          ],
        ),
      ),
    );
  }
}

class _Permission extends StatelessWidget {
  const _Permission({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
  });

  final int number;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: s.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: s.onPrimaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$number. $title', style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: s.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
