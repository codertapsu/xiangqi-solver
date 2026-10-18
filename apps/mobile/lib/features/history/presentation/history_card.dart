import 'package:flutter/material.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../../../core/utils/relative_time.dart';
import '../../solver/domain/engine_score.dart';
import '../../solver/domain/solver_enums.dart';
import '../../solver/presentation/widgets/xiangqi_board.dart';
import '../domain/history_entry.dart';

/// One saved analysis: a small board with the move drawn on it, the move in
/// words, the evaluation and when it was made. Used by History and by Home's
/// "Latest analysis".
class HistoryCard extends StatelessWidget {
  const HistoryCard({super.key, required this.entry, this.onTap, this.highlighted = false});

  final HistoryEntry entry;
  final VoidCallback? onTap;

  /// Draws a primary-coloured outline (the entry a deep link pointed at).
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final s = theme.colorScheme;
    final result = entry.result;
    final move = result?.bestMove;
    final human = move?.human ?? entry.bestMoveHuman;
    final title = (human != null && human.isNotEmpty)
        ? human
        : (move?.uci ?? entry.bestMoveUci ?? l10n.historyNoMove);
    final score = move == null ? null : EngineScore.tryParse(move.score);
    final side = SideToMove.fromWire(entry.sideToMove);

    final details = <String>[
      if (move != null && move.notation.isNotEmpty) move.notation,
      if (score != null && !score.isMate) score.signedPawns,
      if (score != null && score.isMate) 'M${score.mateIn!.abs()}',
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: highlighted
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: s.primary, width: 2),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 84,
                child: result == null
                    ? AspectRatio(
                        aspectRatio: XiangqiBoard.aspectRatio(showCoordinates: false),
                        child: Container(
                          decoration: BoxDecoration(
                            color: s.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.grid_on_rounded, color: s.outline),
                        ),
                      )
                    : ExcludeSemantics(
                        child: XiangqiBoard(
                          pieces: result.board.pieces,
                          move: move == null ? null : BoardArrow(from: move.from, to: move.to),
                          flipped: side == SideToMove.black,
                          showCoordinates: false,
                          animateMove: false,
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (side != SideToMove.unknown) ...[
                          PieceToken(
                            color: side == SideToMove.black ? PieceColor.black : PieceColor.red,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            relativeTime(l10n, entry.timestamp),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: s.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(title, style: theme.textTheme.titleMedium),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        details.join('  •  '),
                        style: theme.textTheme.bodySmall?.copyWith(color: s.onSurfaceVariant),
                      ),
                    ],
                    if (result == null) ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.historyLegacyEntry,
                        style: theme.textTheme.bodySmall?.copyWith(color: s.outline),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right_rounded, color: s.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
