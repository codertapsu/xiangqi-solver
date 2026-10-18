import 'package:flutter/material.dart';
import 'package:xiangqi_solver/core/l10n/enum_l10n.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../../../../app/theme/app_palette.dart';
import '../../domain/solver_enums.dart';
import 'xiangqi_board.dart';

/// Red / Black as two real piece tokens (帥 / 將) — the side the user plays,
/// which the engine treats as the side to move.
///
/// [onHero] styles it for the Home hero's gradient instead of a plain surface.
class SideTokenPicker extends StatelessWidget {
  const SideTokenPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.onHero = false,
  });

  /// Any non-black value is shown as Red.
  final SideToMove value;
  final ValueChanged<SideToMove> onChanged;
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final selected = value == SideToMove.black ? SideToMove.black : SideToMove.red;
    // A Wrap, so Black drops under Red rather than overflowing at large text.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SideToken(
          side: SideToMove.red,
          selected: selected == SideToMove.red,
          onHero: onHero,
          onTap: () => onChanged(SideToMove.red),
        ),
        _SideToken(
          side: SideToMove.black,
          selected: selected == SideToMove.black,
          onHero: onHero,
          onTap: () => onChanged(SideToMove.black),
        ),
      ],
    );
  }
}

class _SideToken extends StatelessWidget {
  const _SideToken({
    required this.side,
    required this.selected,
    required this.onHero,
    required this.onTap,
  });

  final SideToMove side;
  final bool selected;
  final bool onHero;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final label = side.localizedLabel(l10n);

    final Color fill;
    final Color border;
    final Color text;
    if (onHero) {
      fill = selected ? palette.onHero : palette.heroSurface;
      border = selected ? palette.gold : Colors.transparent;
      text = selected ? palette.ink : palette.onHero;
    } else {
      fill = selected
          ? theme.colorScheme.secondaryContainer
          : theme.colorScheme.surfaceContainerHigh;
      border = selected ? palette.gold : theme.colorScheme.outlineVariant;
      text = selected
          ? theme.colorScheme.onSecondaryContainer
          : theme.colorScheme.onSurfaceVariant;
    }

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: border, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PieceToken(
                  color: side == SideToMove.black ? PieceColor.black : PieceColor.red,
                  size: 32,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: text,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
