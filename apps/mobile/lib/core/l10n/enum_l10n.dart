import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../../features/solver/domain/solver_enums.dart';

/// Localized display labels for the enums shown in the UI.
///
/// The enums keep their English `.label` getter (a dev/log fallback); the UI
/// renders these locale-aware variants instead. Brand/technical values
/// (Gemini, OpenAI) are intentionally identical across locales.
extension SideToMoveL10n on SideToMove {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    SideToMove.red => l10n.sideRed,
    SideToMove.black => l10n.sideBlack,
    SideToMove.unknown => l10n.sideUnknown,
  };
}

extension AiProviderL10n on AiProvider {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    AiProvider.auto => l10n.aiProviderAuto,
    AiProvider.gemini => l10n.aiProviderGemini,
    AiProvider.openai => l10n.aiProviderOpenai,
    AiProvider.mock => l10n.providerMock,
  };
}

extension EngineProviderL10n on EngineProvider {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    EngineProvider.pikafish => l10n.engineProviderStandard,
    EngineProvider.mock => l10n.providerMock,
  };
}

extension AiKeySourceL10n on AiKeySource {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    AiKeySource.ours => l10n.aiKeySourceOurs,
    AiKeySource.own => l10n.aiKeySourceOwn,
  };
}

extension EngineLocationL10n on EngineLocation {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    EngineLocation.cloud => l10n.engineLocationCloud,
    EngineLocation.onDevice => l10n.engineLocationOnDevice,
  };
}
