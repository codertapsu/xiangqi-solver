import 'package:flutter/material.dart';

import '../../domain/solver_enums.dart';

/// A two-option segmented control for choosing which side the user plays
/// (whose move it is when solving). Constrained to Red / Black.
///
/// Used on both Home (quick toggle) and Settings so the choice stays in sync
/// via the shared settings store.
class SideSelector extends StatelessWidget {
  const SideSelector({super.key, required this.value, required this.onChanged});

  /// Currently selected side. Any non-black value is treated as red.
  final SideToMove value;

  /// Called with the newly selected side (always red or black).
  final ValueChanged<SideToMove> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == SideToMove.black
        ? SideToMove.black
        : SideToMove.red;
    return SegmentedButton<SideToMove>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment<SideToMove>(
          value: SideToMove.red,
          label: Text('Red'),
          icon: Icon(Icons.circle, color: Color(0xFFD32F2F), size: 14),
        ),
        ButtonSegment<SideToMove>(
          value: SideToMove.black,
          label: Text('Black'),
          icon: Icon(Icons.circle, color: Color(0xFF424242), size: 14),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
