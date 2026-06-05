import 'package:flutter/material.dart';

import '../../domain/solver_enums.dart';

/// Dropdown for selecting the AI (vision) provider.
class AiProviderDropdown extends StatelessWidget {
  const AiProviderDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final AiProvider value;
  final ValueChanged<AiProvider> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<AiProvider>(
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'AI provider',
        prefixIcon: Icon(Icons.visibility_outlined),
      ),
      items: [
        for (final p in AiProvider.values)
          DropdownMenuItem(value: p, child: Text(p.label)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

/// Dropdown for selecting the engine provider.
class EngineProviderDropdown extends StatelessWidget {
  const EngineProviderDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final EngineProvider value;
  final ValueChanged<EngineProvider> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<EngineProvider>(
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Engine provider',
        prefixIcon: Icon(Icons.memory_outlined),
      ),
      items: [
        for (final p in EngineProvider.values)
          DropdownMenuItem(value: p, child: Text(p.label)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
