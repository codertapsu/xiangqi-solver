import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/utils/privacy_policy.dart';
import '../../solver/domain/solver_enums.dart';
import '../../solver/presentation/widgets/xiangqi_board.dart';

/// First-run introduction: what the app does, and — before any screenshot is
/// taken — where screenshots go (the prominent AI/privacy disclosure).
///
/// Completes when the sheet is closed, however that happens.
Future<void> showWelcomeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const WelcomeSheet(),
  );
}

class WelcomeSheet extends StatelessWidget {
  const WelcomeSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    // useSafeArea only guards the top and sides; keep the button above the
    // gesture/navigation bar too. The text scrolls; the button stays in view.
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PieceToken(color: PieceColor.red, size: 52),
                      SizedBox(width: 10),
                      PieceToken(color: PieceColor.black, size: 52),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.welcomeTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.welcomeSubtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _Point(
                    icon: ios
                        ? Icons.ios_share_rounded
                        : Icons.touch_app_rounded,
                    color: palette.cinnabar,
                    title: l10n.welcomeCaptureTitle,
                    body: ios
                        ? l10n.welcomeCaptureBodyIos
                        : l10n.welcomeCaptureBody,
                  ),
                  _Point(
                    icon: Icons.near_me_rounded,
                    color: palette.goldText,
                    title: l10n.welcomeMoveTitle,
                    body: l10n.welcomeMoveBody,
                  ),
                  _Point(
                    icon: Icons.privacy_tip_rounded,
                    color: palette.jade,
                    title: l10n.privacyBannerTitle,
                    body: l10n.privacyBannerBody,
                    trailing: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 40),
                        ),
                        onPressed: () => openPrivacyPolicy(context),
                        child: Text(l10n.settingsPrivacyPolicy),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.welcomeStart),
            ),
          ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.trailing,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
