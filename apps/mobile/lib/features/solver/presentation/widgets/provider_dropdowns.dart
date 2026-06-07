import 'package:flutter/material.dart';
import 'package:xiangqi_solver/core/l10n/enum_l10n.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context);
    return DropdownButtonFormField<AiProvider>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: l10n.providerAiLabel,
        prefixIcon: const Icon(Icons.visibility_outlined),
      ),
      items: [
        for (final p in AiProvider.values)
          DropdownMenuItem(value: p, child: Text(p.localizedLabel(l10n))),
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
    final l10n = AppLocalizations.of(context);
    return DropdownButtonFormField<EngineProvider>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: l10n.providerEngineLabel,
        prefixIcon: const Icon(Icons.memory_outlined),
      ),
      items: [
        for (final p in EngineProvider.values)
          DropdownMenuItem(value: p, child: Text(p.localizedLabel(l10n))),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
