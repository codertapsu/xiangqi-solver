import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/analysis_result.dart';
import '../providers/solver_providers.dart';
import '../widgets/best_move_card.dart';
import '../widgets/section_card.dart';

/// Shows the outcome of the most recent analysis: thumbnail, extracted board
/// JSON, best move, explanation, confidence, and any warnings/errors.
class ResultPage extends ConsumerWidget {
  const ResultPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(analysisProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Analysis Result')),
      body: SafeArea(child: _buildBody(context, status)),
    );
  }

  Widget _buildBody(BuildContext context, AnalysisStatus status) {
    return switch (status) {
      AnalysisIdle() => const _CenteredMessage(
        icon: Icons.info_outline,
        message: 'No analysis yet. Run one from the Home screen.',
      ),
      AnalysisLoading() => const _CenteredMessage(
        icon: Icons.hourglass_top,
        message: 'Analyzing…',
        showSpinner: true,
      ),
      AnalysisError(:final failure) => _CenteredMessage(
        icon: Icons.error_outline,
        message: failure.message,
        detail: failure.code == null ? null : 'Code: ${failure.code}',
      ),
      AnalysisSuccess(:final result, :final screenshotPath) => _ResultContent(
        result: result,
        screenshotPath: screenshotPath,
      ),
    };
  }
}

class _ResultContent extends StatelessWidget {
  const _ResultContent({required this.result, required this.screenshotPath});

  final AnalysisResult result;
  final String? screenshotPath;

  @override
  Widget build(BuildContext context) {
    final board = result.board;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (screenshotPath != null) ...[
          _Thumbnail(path: screenshotPath!),
          const SizedBox(height: 16),
        ],
        _buildPipelineStatus(context),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Best move',
          icon: Icons.flag,
          child: BestMoveCard(move: result.bestMove),
        ),
        if (result.candidates.length > 1) ...[
          const SizedBox(height: 16),
          SectionCard(
            title: 'Top moves',
            icon: Icons.format_list_numbered,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < result.candidates.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            result.candidates[i].human,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          '${result.candidates[i].notation}  ${result.candidates[i].score}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        SectionCard(
          title: 'Explanation',
          icon: Icons.lightbulb_outline,
          child: Text(
            result.explanation.isEmpty
                ? 'No explanation provided.'
                : result.explanation,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Board',
          icon: Icons.grid_on,
          trailing: _ConfidenceBadge(confidence: board.confidence),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Side to move: ${board.sideToMove.label} • '
                '${board.pieces.length} pieces',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (board.fen.isNotEmpty) ...[
                const SizedBox(height: 8),
                SelectableText(
                  'FEN: ${board.fen}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              _JsonBlock(json: result.prettyBoardJson()),
            ],
          ),
        ),
        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 16),
          _WarningsCard(warnings: result.warnings),
        ],
      ],
    );
  }

  Widget _buildPipelineStatus(BuildContext context) {
    return SectionCard(
      title: 'Pipeline',
      icon: Icons.account_tree_outlined,
      child: Row(
        children: [
          Expanded(
            child: _ProviderStatusTile(
              label: 'Vision',
              provider: result.vision.provider,
              ok: result.vision.ok,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ProviderStatusTile(
              label: 'Engine',
              provider: result.engine.provider,
              ok: result.engine.ok,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderStatusTile extends StatelessWidget {
  const _ProviderStatusTile({
    required this.label,
    required this.provider,
    required this.ok,
  });

  final String label;
  final String provider;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = ok ? scheme.primary : scheme.error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                Text(
                  provider,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.confidence});

  final double confidence;

  @override
  Widget build(BuildContext context) {
    final pct = (confidence.clamp(0, 1) * 100).toStringAsFixed(0);
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: const Icon(Icons.verified_outlined, size: 16),
      label: Text('$pct%'),
    );
  }
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.json});

  final String json;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        json,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}

class _WarningsCard extends StatelessWidget {
  const _WarningsCard({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: 'Warnings',
      icon: Icons.warning_amber_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.chevron_right, size: 18, color: scheme.error),
                  Expanded(
                    child: Text(
                      w,
                      style: Theme.of(context).textTheme.bodySmall,
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

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => Container(
            height: 120,
            alignment: Alignment.center,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Text('Screenshot preview unavailable'),
          ),
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.message,
    this.detail,
    this.showSpinner = false,
  });

  final IconData icon;
  final String message;
  final String? detail;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSpinner)
              const CircularProgressIndicator()
            else
              Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
