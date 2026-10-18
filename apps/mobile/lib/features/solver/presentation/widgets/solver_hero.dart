import 'package:flutter/material.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../../../../app/theme/app_palette.dart';
import '../../domain/solver_enums.dart';
import 'side_token_picker.dart';

/// The lacquer-red card at the top of Home that carries the app's one main
/// action (docs/DESIGN.md §5 "Home").
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: palette.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: palette.cinnabar.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: palette.onHero),
          child: IconTheme.merge(
            data: IconThemeData(color: palette.onHero),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Android: start/stop Solver Mode and pick the side you play.
class SolverHero extends StatelessWidget {
  const SolverHero({
    super.key,
    required this.running,
    required this.busy,
    required this.side,
    required this.onSideChanged,
    required this.onStart,
    required this.onStop,
  });

  final bool running;
  final bool busy;
  final SideToMove side;
  final ValueChanged<SideToMove> onSideChanged;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return HeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _Seal(icon: Icons.auto_awesome_rounded),
              const SizedBox(width: 12),
              // Title over status, so neither squeezes the other.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.homeSolverMode,
                      style: theme.textTheme.titleLarge?.copyWith(color: palette.onHero),
                    ),
                    const SizedBox(height: 4),
                    _StatusPill(running: running),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            running ? l10n.homeSolverRunningHint : l10n.homeSolverModeDesc,
            style: theme.textTheme.bodyMedium?.copyWith(color: palette.onHeroMuted),
          ),
          const SizedBox(height: 18),
          _SideRow(side: side, onChanged: onSideChanged),
          const SizedBox(height: 18),
          _HeroButton(
            running: running,
            busy: busy,
            onStart: onStart,
            onStop: onStop,
          ),
        ],
      ),
    );
  }
}

/// iOS: no overlay or on-demand capture, so the hero offers the share-in /
/// pick-a-photo flow instead (docs/IOS_PORT.md).
class ShareHero extends StatelessWidget {
  const ShareHero({
    super.key,
    required this.busy,
    required this.side,
    required this.onSideChanged,
    required this.onPick,
  });

  final bool busy;
  final SideToMove side;
  final ValueChanged<SideToMove> onSideChanged;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return HeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _Seal(icon: Icons.ios_share_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.homeShareInTitle,
                  style: theme.textTheme.titleLarge?.copyWith(color: palette.onHero),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            l10n.homeShareInDesc,
            style: theme.textTheme.bodyMedium?.copyWith(color: palette.onHeroMuted),
          ),
          const SizedBox(height: 18),
          _SideRow(side: side, onChanged: onSideChanged),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: _primaryStyle(context),
            onPressed: busy ? null : onPick,
            icon: busy ? const _ButtonSpinner() : const Icon(Icons.photo_library_rounded),
            label: Text(l10n.homePickPhoto),
          ),
        ],
      ),
    );
  }
}

class _SideRow extends StatelessWidget {
  const _SideRow({required this.side, required this.onChanged});

  final SideToMove side;
  final ValueChanged<SideToMove> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    // A Wrap, so the picker drops below the label at large font scales.
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.homeYouPlay,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: palette.onHero),
        ),
        SideTokenPicker(value: side, onChanged: onChanged, onHero: true),
      ],
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.running,
    required this.busy,
    required this.onStart,
    required this.onStop,
  });

  final bool running;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    if (running) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.onHero,
          side: BorderSide(color: palette.onHero.withValues(alpha: 0.7), width: 1.5),
        ),
        onPressed: busy ? null : onStop,
        icon: busy ? const _ButtonSpinner() : const Icon(Icons.stop_rounded),
        label: Text(l10n.homeSolverStop),
      );
    }
    return FilledButton.icon(
      style: _primaryStyle(context),
      onPressed: busy ? null : onStart,
      icon: busy ? const _ButtonSpinner() : const Icon(Icons.play_arrow_rounded),
      label: Text(l10n.homeSolverStart),
    );
  }
}

/// A cream (light) / gold (dark) button that reads clearly on the hero.
ButtonStyle _primaryStyle(BuildContext context) {
  final palette = AppPalette.of(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  final bg = dark ? palette.gold : palette.onHero;
  final fg = dark ? const Color(0xFF3A2900) : palette.cinnabar;
  return FilledButton.styleFrom(
    backgroundColor: bg,
    foregroundColor: fg,
    disabledBackgroundColor: bg.withValues(alpha: 0.6),
    disabledForegroundColor: fg.withValues(alpha: 0.7),
    textStyle: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
  );
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2.2),
    );
  }
}

/// The round "seal" badge at the hero's top-left.
class _Seal extends StatelessWidget {
  const _Seal({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.heroSurface,
        border: Border.all(color: palette.gold.withValues(alpha: 0.8), width: 1.5),
      ),
      child: Icon(icon, color: palette.gold, size: 22),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.running});

  final bool running;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final dot = running ? const Color(0xFF7BE0A8) : palette.onHeroMuted.withValues(alpha: 0.7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: palette.heroSurface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            running ? l10n.homeSolverOn : l10n.homeSolverOff,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: palette.onHero,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
