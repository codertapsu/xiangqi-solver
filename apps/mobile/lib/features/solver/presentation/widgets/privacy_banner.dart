import 'package:flutter/material.dart';

/// A prominent, dismissible-free banner explaining data/training implications.
///
/// Shown on Home so users understand that screenshots are uploaded for
/// analysis and may be processed by third-party AI providers.
class PrivacyBanner extends StatelessWidget {
  const PrivacyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.privacy_tip_outlined, color: scheme.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Privacy & AI use',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'To read the board, the screenshot you analyze is sent to '
                  'OpenAI — through our service, or directly if you use your own '
                  'API key. Images aren\'t saved on this device unless you turn '
                  'on history in Settings. Avoid capturing sensitive content.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onTertiaryContainer,
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
