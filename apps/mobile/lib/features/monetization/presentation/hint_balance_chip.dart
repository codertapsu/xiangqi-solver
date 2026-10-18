import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../../../app/theme/app_palette.dart';
import 'get_more_hints_sheet.dart';
import 'wallet_providers.dart';

/// App-bar "coin" showing the device-local hint balance; tap to open the "get
/// more hints" sheet.
class HintBalanceChip extends ConsumerWidget {
  const HintBalanceChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final balance = ref.watch(walletProvider);
    final empty = balance <= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Tooltip(
        message: l10n.hintsChipTooltip,
        child: Material(
          color: empty ? theme.colorScheme.errorContainer : palette.gold.withValues(alpha: 0.18),
          shape: StadiumBorder(
            side: BorderSide(
              color: empty ? theme.colorScheme.error : palette.gold.withValues(alpha: 0.7),
            ),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => showGetMoreHintsSheet(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36, minWidth: 48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lightbulb_rounded,
                      size: 18,
                      color: empty ? theme.colorScheme.error : palette.goldText,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$balance',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: empty
                            ? theme.colorScheme.onErrorContainer
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
