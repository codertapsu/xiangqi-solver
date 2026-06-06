import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'get_more_hints_sheet.dart';
import 'wallet_providers.dart';

/// App-bar chip showing the device-local hint balance; tap to open the "get
/// more hints" sheet. Show this only in "our service" (cloud) mode.
class HintBalanceChip extends ConsumerWidget {
  const HintBalanceChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(walletProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: ActionChip(
        avatar: const Icon(Icons.lightbulb_outline, size: 18),
        label: Text('$balance'),
        tooltip: 'Hints — tap to get more',
        onPressed: () => showGetMoreHintsSheet(context),
      ),
    );
  }
}
