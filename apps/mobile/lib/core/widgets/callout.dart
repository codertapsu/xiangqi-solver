import 'package:flutter/material.dart';

/// The intent of a [Callout], which picks its colours and default icon.
enum CalloutTone { info, warning, error, success }

/// A tinted inline notice: an icon, an optional title, and a body.
class Callout extends StatelessWidget {
  const Callout({
    super.key,
    required this.tone,
    required this.child,
    this.title,
    this.icon,
    this.action,
  });

  final CalloutTone tone;
  final String? title;
  final Widget child;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final (Color bg, Color fg, IconData defaultIcon) = switch (tone) {
      CalloutTone.info => (s.secondaryContainer, s.onSecondaryContainer, Icons.info_outline_rounded),
      CalloutTone.warning => (s.primaryContainer, s.onPrimaryContainer, Icons.warning_amber_rounded),
      CalloutTone.error => (s.errorContainer, s.onErrorContainer, Icons.error_outline_rounded),
      CalloutTone.success => (s.tertiaryContainer, s.onTertiaryContainer, Icons.check_circle_outline_rounded),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(Radius.circular(16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, color: fg, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: DefaultTextStyle.merge(
              style: theme.textTheme.bodyMedium?.copyWith(color: fg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      style: theme.textTheme.titleSmall?.copyWith(color: fg),
                    ),
                    const SizedBox(height: 4),
                  ],
                  child,
                  if (action != null) ...[const SizedBox(height: 8), action!],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
