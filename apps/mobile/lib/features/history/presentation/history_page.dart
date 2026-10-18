import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../../../app/router.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/screenshot_preview.dart';
import '../../solver/presentation/providers/solver_providers.dart';
import '../domain/history_entry.dart';
import 'history_card.dart';

/// Past analyses, newest first. Tap one to reopen it on the board; swipe it
/// away to delete (with undo).
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key, this.selectedId});

  /// Optional analysis id to highlight (passed via route query param).
  final String? selectedId;

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  /// Swiped away, waiting for the undo window to pass before the delete commits.
  final Set<String> _pendingDelete = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = ref
        .watch(historyListProvider)
        .where((e) => !_pendingDelete.contains(e.analysisId))
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.historyTitle),
        actions: [
          if (entries.isNotEmpty)
            IconButton(
              tooltip: l10n.historyClear,
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: SafeArea(
        child: entries.isEmpty
            ? EmptyState(
                icon: Icons.history_rounded,
                title: l10n.historyEmptyTitle,
                message: l10n.historyEmptyBody,
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return Dismissible(
                    key: ValueKey(entry.analysisId),
                    direction: DismissDirection.endToStart,
                    background: const _DeleteBackground(),
                    onDismissed: (_) => _delete(entry),
                    child: HistoryCard(
                      entry: entry,
                      highlighted: entry.analysisId == widget.selectedId,
                      onTap: () => _open(entry),
                    ),
                  );
                },
              ),
      ),
    );
  }

  void _open(HistoryEntry entry) {
    if (entry.result != null) {
      context.push(AppRoutes.historyEntry(entry.analysisId));
    } else {
      // Saved by 1.0 (no board kept): show what we have.
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _LegacyDetails(entry: entry),
      );
    }
  }

  /// Hides the entry now and deletes it once the undo snackbar goes away
  /// without "Undo" being pressed.
  void _delete(HistoryEntry entry) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(historyRepositoryProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _pendingDelete.add(entry.analysisId));
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final snack = messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.historyDeleted),
        persist: false,
        action: SnackBarAction(label: l10n.actionUndo, onPressed: () {}),
      ),
    );
    unawaited(
      snack.closed.then((reason) async {
        if (reason != SnackBarClosedReason.action) {
          await repo.remove(entry.analysisId);
          container.invalidate(historyListProvider);
        }
        if (mounted) setState(() => _pendingDelete.remove(entry.analysisId));
      }),
    );
  }

  Future<void> _confirmClear() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_sweep_outlined),
        title: Text(l10n.historyClearTitle),
        content: Text(l10n.historyClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.actionClear),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(historyRepositoryProvider).clear();
      ref.invalidate(historyListProvider);
    }
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: s.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.actionDelete,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: s.onErrorContainer),
          ),
          const SizedBox(width: 8),
          Icon(Icons.delete_outline_rounded, color: s.onErrorContainer),
        ],
      ),
    );
  }
}

/// What a pre-1.1 entry kept: ids, providers, the move as text, the screenshot.
class _LegacyDetails extends StatelessWidget {
  const _LegacyDetails({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pct = l10n.percentValue((entry.confidence.clamp(0, 1) * 100).round());
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            entry.bestMoveHuman ?? entry.bestMoveUci ?? l10n.historyNoMove,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          _DetailRow(label: l10n.historyBestMoveUci, value: entry.bestMoveUci ?? '—'),
          _DetailRow(label: l10n.historySideToMove, value: entry.sideToMove),
          _DetailRow(label: l10n.historyVisionProvider, value: entry.aiProvider),
          _DetailRow(label: l10n.historyEngineProvider, value: entry.engineProvider),
          _DetailRow(label: l10n.historyConfidence, value: pct),
          _DetailRow(label: l10n.historyAnalysisId, value: entry.analysisId),
          if (entry.screenshotPath != null) ...[
            const SizedBox(height: 12),
            ScreenshotPreview(path: entry.screenshotPath!),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
