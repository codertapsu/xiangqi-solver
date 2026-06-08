import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../../solver/presentation/providers/solver_providers.dart';
import '../../solver/presentation/widgets/section_card.dart';
import '../domain/history_entry.dart';

/// Lists previous analyses (local metadata only). Tapping an entry expands its
/// details inline.
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key, this.selectedId});

  /// Optional analysis id to auto-expand (passed via route query param).
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entries = ref.watch(historyListProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.historyTitle),
        actions: [
          if (entries.isNotEmpty)
            IconButton(
              tooltip: l10n.historyClear,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmClear(context, ref),
            ),
        ],
      ),
      body: SafeArea(
        child: entries.isEmpty
            ? const _EmptyHistory()
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return _HistoryTile(
                    entry: entry,
                    initiallyExpanded: entry.analysisId == selectedId,
                  );
                },
              ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
      // Nudge dependents to recompute by resetting analysis state.
      ref.read(analysisProvider.notifier).reset();
    }
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.initiallyExpanded});

  final HistoryEntry entry;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatted = DateFormat.yMMMd().add_Hms().format(entry.timestamp);
    final pctValue = (entry.confidence.clamp(0, 1) * 100).round();
    final pct = l10n.percentValue(pctValue);
    return Card(
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        shape: const Border(),
        leading: const Icon(Icons.history),
        title: Text(entry.bestMoveUci ?? l10n.historyNoMove),
        subtitle: Text('$formatted • ${entry.aiProvider} • $pct'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _DetailRow(label: l10n.historyAnalysisId, value: entry.analysisId),
          _DetailRow(label: l10n.historySideToMove, value: entry.sideToMove),
          _DetailRow(
            label: l10n.historyBestMoveUci,
            value: entry.bestMoveUci ?? '—',
          ),
          _DetailRow(
            label: l10n.historyBestMove,
            value: entry.bestMoveHuman ?? '—',
          ),
          _DetailRow(label: l10n.historyVisionProvider, value: entry.aiProvider),
          _DetailRow(
            label: l10n.historyEngineProvider,
            value: entry.engineProvider,
          ),
          _DetailRow(label: l10n.historyConfidence, value: pct),
          if (entry.screenshotPath != null)
            _ScreenshotPreview(path: entry.screenshotPath!),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders the saved screenshot for a history entry as an inline image (tap to
/// view full-screen). Falls back to a placeholder if the file was deleted.
class _ScreenshotPreview extends StatelessWidget {
  const _ScreenshotPreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final file = File(path);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.historyScreenshot, style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Material(
              color: theme.colorScheme.surfaceContainerHighest,
              child: InkWell(
                onTap: () => _openFullScreen(context, file),
                child: Image.file(
                  file,
                  width: double.infinity,
                  height: 220,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, error, stack) => _unavailable(theme, l10n),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unavailable(ThemeData theme, AppLocalizations l10n) {
    return SizedBox(
      height: 96,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: theme.colorScheme.outline),
            const SizedBox(height: 6),
            Text(
              l10n.resultScreenshotUnavailable,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  void _openFullScreen(BuildContext context, File file) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            // Pinch-to-zoom; tap the backdrop to dismiss.
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Center(
                  child: Image.file(
                    file,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: SectionCard(
          title: l10n.historyEmptyTitle,
          icon: Icons.history_toggle_off,
          child: Text(
            l10n.historyEmptyBody,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}
