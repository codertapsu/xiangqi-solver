import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../constants/app_constants.dart';

/// Opens the public privacy policy in the browser; a snackbar if that fails.
Future<void> openPrivacyPolicy(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final message = AppLocalizations.of(context).settingsPrivacyOpenFailed;
  var ok = false;
  try {
    ok = await launchUrl(
      Uri.parse(AppConstants.privacyPolicyUrl),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    ok = false;
  }
  if (!ok) {
    messenger
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The full "where do my screenshots go" disclosure, with a policy link.
Future<void> showPrivacyDetails(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.privacy_tip_outlined),
      title: Text(l10n.privacyBannerTitle),
      content: SingleChildScrollView(child: Text(l10n.privacyBannerBody)),
      actions: [
        TextButton(
          onPressed: () => openPrivacyPolicy(context),
          child: Text(l10n.settingsPrivacyPolicy),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.actionClose),
        ),
      ],
    ),
  );
}
