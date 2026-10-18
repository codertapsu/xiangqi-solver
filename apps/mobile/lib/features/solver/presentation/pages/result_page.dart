import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:xiangqi_solver/core/l10n/enum_l10n.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../../core/widgets/callout.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/screenshot_preview.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../monetization/presentation/get_more_hints_sheet.dart';
import '../../domain/analysis_result.dart';
import '../../domain/best_move.dart';
import '../../domain/board_state.dart';
import '../../domain/engine_score.dart';
import '../../domain/solver_enums.dart';
import '../providers/solver_providers.dart';
import '../widgets/xiangqi_board.dart';

/// The outcome of the most recent analysis — or, with [historyId], a saved one.
///
/// Board first (docs/DESIGN.md §5): the recognized position with the best move
/// drawn as an arrow, the move in words, how the position stands, other good
/// moves, and — collapsed — the technical details.
class ResultPage extends ConsumerWidget {
  const ResultPage({super.key, this.historyId});

  /// When set, show this history entry instead of the live analysis.
  final String? historyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final id = historyId;
    if (id != null) {
      final entry = ref.watch(historyRepositoryProvider).findById(id);
      final result = entry?.result;
      return Scaffold(
        appBar: AppBar(title: Text(l10n.resultTitle)),
        body: SafeArea(
          child: result == null
              ? EmptyState(
                  icon: Icons.history_toggle_off_rounded,
                  title: l10n.resultSavedUnavailableTitle,
                  message: l10n.resultSavedUnavailableBody,
                )
              : ResultView(
                  result: result,
                  screenshotPath: entry!.screenshotPath,
                  savedAt: entry.timestamp,
                ),
        ),
      );
    }

    final status = ref.watch(analysisProvider);
    // A small tap of feedback when the answer lands.
    ref.listen<AnalysisStatus>(analysisProvider, (prev, next) {
      if (next is AnalysisSuccess && prev is! AnalysisSuccess) {
        HapticFeedback.lightImpact();
      }
    });
    return Scaffold(
      appBar: AppBar(title: Text(l10n.resultTitle)),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: switch (status) {
            AnalysisIdle() => EmptyState(
              key: const ValueKey('idle'),
              icon: Icons.grid_on_rounded,
              title: l10n.resultIdleTitle,
              message: l10n.resultIdleBody,
              action: FilledButton(
                onPressed: () => context.pop(),
                child: Text(l10n.actionBackHome),
              ),
            ),
            AnalysisLoading(:final board) => _LoadingView(
              key: const ValueKey('loading'),
              board: board,
            ),
            AnalysisError(:final failure) => _ErrorView(
              key: const ValueKey('error'),
              failure: failure,
            ),
            AnalysisSuccess(:final result, :final screenshotPath) => ResultView(
              key: ValueKey(result.analysisId),
              result: result,
              screenshotPath: screenshotPath,
            ),
          },
        ),
      ),
    );
  }
}

/// A finished analysis: headline, board, other moves, warnings, details.
class ResultView extends StatefulWidget {
  const ResultView({
    super.key,
    required this.result,
    this.screenshotPath,
    this.savedAt,
  });

  final AnalysisResult result;
  final String? screenshotPath;

  /// When this is a saved (history) result, when it was saved.
  final DateTime? savedAt;

  @override
  State<ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<ResultView> {
  /// Index into [_moves] of the move shown on the board (0 = the best move).
  int _selected = 0;

  List<BestMove> get _moves {
    final r = widget.result;
    if (r.candidates.isNotEmpty) return r.candidates;
    return [?r.bestMove];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final result = widget.result;
    final moves = _moves;
    final shown = moves.isEmpty ? null : moves[_selected.clamp(0, moves.length - 1)];
    // The side to move is the side the user played, so Black plays "up" the
    // board — the way their game app showed it.
    final flipped = result.board.sideToMove == SideToMove.black;
    final savedAt = widget.savedAt;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        if (savedAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 4),
            child: Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(relativeTime(l10n, savedAt), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        _MoveHeadline(
          move: shown,
          side: result.board.sideToMove,
          isBest: _selected == 0,
          rank: _selected + 1,
        ),
        const SizedBox(height: 16),
        _BoardCard(
          board: result.board,
          move: shown,
          flipped: flipped,
          semanticsLabel: _boardLabel(l10n, result.board.sideToMove, shown),
        ),
        if (moves.length > 1) ...[
          const SizedBox(height: 24),
          SectionHeader(l10n.resultTopMoves),
          _MovesList(
            moves: moves,
            side: result.board.sideToMove,
            selected: _selected,
            onSelect: (i) => setState(() => _selected = i),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              l10n.resultTapToPreview,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 24),
          Callout(
            tone: CalloutTone.warning,
            title: l10n.resultWarnings,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final w in result.warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $w'),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        _TechnicalDetails(result: result, screenshotPath: widget.screenshotPath),
      ],
    );
  }

  String _boardLabel(AppLocalizations l10n, SideToMove side, BestMove? move) {
    final sideLabel = side.localizedLabel(l10n);
    if (move == null) return l10n.boardSemanticsNoMove(sideLabel);
    return l10n.boardSemantics(sideLabel, move.human.isNotEmpty ? move.human : move.uci);
  }
}

/// The move in words, who plays it, and how the position stands.
class _MoveHeadline extends StatelessWidget {
  const _MoveHeadline({
    required this.move,
    required this.side,
    required this.isBest,
    required this.rank,
  });

  final BestMove? move;
  final SideToMove side;
  final bool isBest;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final m = move;
    final pieceColor = side == SideToMove.black ? PieceColor.black : PieceColor.red;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PieceToken(color: pieceColor, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.sideToMoveLabel(side.localizedLabel(l10n)),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (m != null)
                  _Badge(
                    label: isBest ? l10n.resultBestBadge : l10n.resultOptionBadge(rank),
                    color: isBest ? palette.gold : theme.colorScheme.outlineVariant,
                    textColor: isBest ? const Color(0xFF3A2900) : theme.colorScheme.onSurface,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              m == null ? l10n.statusNoMove : (m.human.isNotEmpty ? m.human : m.uci),
              style: theme.textTheme.headlineMedium?.copyWith(height: 1.15),
            ),
            if (m == null) ...[
              const SizedBox(height: 6),
              Text(l10n.bestMoveNone, style: theme.textTheme.bodyMedium),
            ] else ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (m.notation.isNotEmpty) _Pill(text: m.notation, mono: true),
                  if (m.depth > 0) _Pill(text: l10n.resultDepth(m.depth)),
                ],
              ),
              if (EngineScore.tryParse(m.score) case final score?) ...[
                const SizedBox(height: 18),
                EvalMeter(score: score, side: side),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// A two-tone bar plus plain words for how the side to move stands.
class EvalMeter extends StatelessWidget {
  const EvalMeter({super.key, required this.score, required this.side});

  final EngineScore score;
  final SideToMove side;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final redColor = palette.cinnabar;
    final blackColor = isDark ? theme.colorScheme.onSurfaceVariant : palette.ink;
    final moverIsBlack = side == SideToMove.black;
    // The bar always reads Red on the left, Black on the right.
    final redShare = moverIsBlack ? 1 - score.share : score.share;
    final figure = score.isMate ? '' : score.signedPawns;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.insights_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                verdictText(l10n, score, side),
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (figure.isNotEmpty)
              Text(
                figure,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Semantics(
          label: verdictText(l10n, score, side),
          excludeSemantics: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                // Stretch: a childless ColoredBox is otherwise 0 px tall.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: (redShare * 1000).round().clamp(1, 999),
                    child: ColoredBox(color: redColor),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: ((1 - redShare) * 1000).round().clamp(1, 999),
                    child: ColoredBox(color: blackColor),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(l10n.sideRed, style: theme.textTheme.labelSmall?.copyWith(color: redColor)),
            const Spacer(),
            Text(l10n.sideBlack, style: theme.textTheme.labelSmall?.copyWith(color: blackColor)),
          ],
        ),
      ],
    );
  }

  /// How [side] (the side to move) stands, in words.
  static String verdictText(AppLocalizations l10n, EngineScore score, SideToMove side) {
    final s = side.localizedLabel(l10n);
    return switch (score.verdict) {
      EvalVerdict.even => l10n.evalEven,
      EvalVerdict.slightEdge => l10n.evalSlightEdge(s),
      EvalVerdict.advantage => l10n.evalAdvantage(s),
      EvalVerdict.winning => l10n.evalWinning(s),
      EvalVerdict.slightlyWorse => l10n.evalSlightlyWorse(s),
      EvalVerdict.worse => l10n.evalWorse(s),
      EvalVerdict.losing => l10n.evalLosing(s),
      EvalVerdict.mate => l10n.evalMateIn(s, score.mateIn!.abs()),
      EvalVerdict.mated => l10n.evalMatedIn(s, score.mateIn!.abs()),
    };
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.board,
    required this.move,
    required this.flipped,
    required this.semanticsLabel,
  });

  final BoardState board;
  final BestMove? move;
  final bool flipped;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final m = move;
    final pct = (board.confidence.clamp(0, 1) * 100).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Column(
          children: [
            XiangqiBoard(
              pieces: board.pieces,
              move: m == null ? null : BoardArrow(from: m.from, to: m.to),
              flipped: flipped,
              semanticsLabel: semanticsLabel,
            ),
            const SizedBox(height: 10),
            Text(
              l10n.resultBoardCaption(board.pieces.length, pct),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The engine's ranked moves; tapping one redraws it on the board.
class _MovesList extends StatelessWidget {
  const _MovesList({
    required this.moves,
    required this.side,
    required this.selected,
    required this.onSelect,
  });

  final List<BestMove> moves;
  final SideToMove side;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < moves.length; i++) ...[
            if (i > 0) const Divider(indent: 64),
            ListTile(
              selected: i == selected,
              selectedTileColor: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
              onTap: () => onSelect(i),
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: i == 0 ? palette.gold : theme.colorScheme.surfaceContainerHighest,
                foregroundColor: i == 0 ? const Color(0xFF3A2900) : theme.colorScheme.onSurface,
                child: Text('${i + 1}', style: theme.textTheme.labelLarge?.copyWith(color: null)),
              ),
              title: Text(moves[i].human.isNotEmpty ? moves[i].human : moves[i].uci),
              subtitle: Text(_subtitle(l10n, moves[i], side)),
              trailing: i == selected
                  ? Icon(Icons.visibility_rounded, color: theme.colorScheme.primary)
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  static String _subtitle(AppLocalizations l10n, BestMove m, SideToMove side) {
    final score = EngineScore.tryParse(m.score);
    final parts = [
      if (m.notation.isNotEmpty) m.notation,
      if (score != null)
        score.isMate ? EvalMeter.verdictText(l10n, score, side) : score.signedPawns,
    ];
    return parts.join('  •  ');
  }
}

/// Everything an expert (or support) might want, collapsed by default.
class _TechnicalDetails extends StatelessWidget {
  const _TechnicalDetails({required this.result, required this.screenshotPath});

  final AnalysisResult result;
  final String? screenshotPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final m = result.bestMove;
    final pct = (result.board.confidence.clamp(0, 1) * 100).round();
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.tune_rounded),
        title: Text(l10n.resultTechnicalDetails),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (screenshotPath != null) ...[
            ScreenshotPreview(path: screenshotPath!),
            const SizedBox(height: 12),
          ],
          _DetailRow(
            label: l10n.pipelineVision,
            value: _prettyProvider(l10n, result.vision.provider),
            ok: result.vision.ok,
          ),
          _DetailRow(
            label: l10n.pipelineEngine,
            value: _prettyProvider(l10n, result.engine.provider),
            ok: result.engine.ok,
          ),
          _DetailRow(label: l10n.historyConfidence, value: l10n.percentValue(pct)),
          if (m != null) ...[
            _DetailRow(label: l10n.labelUci, value: m.uci, copyable: true),
            _DetailRow(label: l10n.labelScore, value: m.score),
          ],
          if (result.board.fen.isNotEmpty)
            _DetailRow(label: 'FEN', value: result.board.fen, copyable: true, mono: true),
          if (result.explanation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(l10n.resultExplanation, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(result.explanation, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          _JsonBox(json: result.prettyBoardJson()),
        ],
      ),
    );
  }

  /// Display names: brand-neutral for the engine (its own name stays
  /// internal), product names for the vision AI.
  static String _prettyProvider(AppLocalizations l10n, String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('pikafish')) {
      return lower.contains('on-device') ? l10n.engineOnDevice : l10n.engineCloud;
    }
    if (lower.startsWith('openai')) return l10n.aiProviderOpenai;
    if (lower.startsWith('gemini')) return l10n.aiProviderGemini;
    if (lower == 'mock') return l10n.providerMock;
    return raw;
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.ok,
    this.copyable = false,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool? ok;
  final bool copyable;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (ok != null) ...[
            Icon(
              ok! ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 16,
              color: ok! ? theme.colorScheme.tertiary : theme.colorScheme.error,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: mono ? 'monospace' : null,
                letterSpacing: mono ? 0 : null,
              ),
            ),
          ),
          if (copyable) ...[
            const SizedBox(width: 8),
            Icon(Icons.copy_rounded, size: 16, color: theme.colorScheme.primary),
          ],
        ],
      ),
    );
    if (!copyable) return row;
    // The whole row copies — a bigger target than a lone icon.
    return Semantics(
      button: true,
      hint: l10n.actionCopy,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _copy(context, value),
        child: row,
      ),
    );
  }
}

class _JsonBox extends StatelessWidget {
  const _JsonBox({required this.json});

  final String json;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(l10n.resultRawData, style: theme.textTheme.labelLarge)),
            TextButton.icon(
              onPressed: () => _copy(context, json),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(l10n.actionCopy),
            ),
          ],
        ),
        Container(
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              json,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _copy(BuildContext context, String value) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: value));
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(l10n.resultCopied)));
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.mono = false});

  final String text;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
          letterSpacing: mono ? 0.6 : null,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, required this.textColor});

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// While the solve runs: the recognized board as soon as it is known.
class _LoadingView extends ConsumerWidget {
  const _LoadingView({super.key, required this.board});

  final BoardState? board;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final b = board;
    final side = b?.sideToMove ?? ref.watch(settingsProvider.select((s) => s.mySide));
    final flipped = side == SideToMove.black;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b == null ? l10n.resultReadingBoard : l10n.statusBoardRecognized(b.pieces.length),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  b == null ? l10n.resultReadingBoardHint : l10n.statusComputingMove,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: b == null ? 0.55 : 1,
              child: XiangqiBoard(
                pieces: b?.pieces ?? const [],
                flipped: flipped,
                semanticsLabel: l10n.statusAnalyzing,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A failed solve, with the actions that can fix it.
class _ErrorView extends ConsumerWidget {
  const _ErrorView({super.key, required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notifier = ref.read(analysisProvider.notifier);
    final outOfHints = failure.code == 'NO_HINTS';
    return EmptyState(
      icon: outOfHints ? Icons.lightbulb_outline_rounded : Icons.cloud_off_rounded,
      title: outOfHints ? l10n.resultOutOfHintsTitle : l10n.statusAnalysisFailed,
      message: failure.message,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (outOfHints)
            FilledButton.icon(
              onPressed: () => showGetMoreHintsSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.hintsGetMore),
            ),
          if (notifier.canRetry) ...[
            const SizedBox(height: 8),
            (outOfHints ? OutlinedButton.icon : FilledButton.icon)(
              onPressed: () => notifier.retry(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.actionRetry),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(onPressed: () => context.pop(), child: Text(l10n.actionBackHome)),
          if (failure.code != null && !outOfHints)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.resultErrorCode(failure.code!),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
        ],
      ),
    );
  }
}
