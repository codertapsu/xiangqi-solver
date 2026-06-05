import 'package:flutter/material.dart';

import '../../domain/best_move.dart';

/// Displays the engine's recommended move (UCI + human notation, score, depth).
class BestMoveCard extends StatelessWidget {
  const BestMoveCard({super.key, required this.move});

  /// The move to display, or null when no move was returned.
  final BestMove? move;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = move;
    if (m == null) {
      return Text(
        'No move available for this position.',
        style: theme.textTheme.bodyMedium,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.flag, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                m.human.isNotEmpty ? m.human : m.uci,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (m.notation.isNotEmpty) _Chip(label: 'WXF', value: m.notation),
            _Chip(label: 'UCI', value: m.uci),
            _Chip(label: 'Score', value: m.score),
            _Chip(label: 'Depth', value: '${m.depth}'),
            _Chip(
              label: 'From',
              value: '(${m.from.file},${m.from.rank})',
            ),
            _Chip(label: 'To', value: '(${m.to.file},${m.to.rank})'),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text('$label: $value'),
    );
  }
}
