// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Xiangqi Strategist';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionClose => 'Close';

  @override
  String get actionOpenSettings => 'Open Settings';

  @override
  String get actionStart => 'Start';

  @override
  String get actionStop => 'Stop';

  @override
  String get actionSave => 'Save';

  @override
  String get actionClear => 'Clear';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionShow => 'Show';

  @override
  String get actionHide => 'Hide';

  @override
  String get tooltipHistory => 'History';

  @override
  String get tooltipSettings => 'Settings';

  @override
  String get homeServerSwitchedOnDevice =>
      'The server is unavailable — switched to On-device Mode.';

  @override
  String get homeNoModeTitle => 'No analysis mode available';

  @override
  String get homeNoModeBody =>
      'The server can\'t be reached and On-device Mode isn\'t set up yet.\n\nAdd your own OpenAI API key in Settings to analyze on your device, or try again when the server is back online.';

  @override
  String homeImagePickerError(String error) {
    return 'Couldn\'t open the image picker: $error';
  }

  @override
  String get homeSolverMode => 'Solver Mode';

  @override
  String get homeSolverModeDesc =>
      'Opens a floating button and screen capture so you can analyze the board inside any app.';

  @override
  String get homeSolverModeUnsupported =>
      'Solver Mode needs a real Android device. Everything else still works here for testing.';

  @override
  String get homeYourSide => 'Your side';

  @override
  String get homeYourSideDesc => 'Whose turn it is when you analyze.';

  @override
  String get homeTryMockTitle => 'Try it (test mode)';

  @override
  String get homeTryMockDesc =>
      'Pick an image to run the full upload and analysis flow without screen capture.';

  @override
  String get homePickImage => 'Pick an image & analyze (test)';

  @override
  String get homeShareInTitle => 'Analyze a board photo';

  @override
  String get homeShareInDesc =>
      'Screenshot your Xiangqi game in any app, then share it into this app — or pick a photo below. We\'ll read the board and show the best move.';

  @override
  String get backendTitle => 'Backend';

  @override
  String get backendUrlLabel => 'Backend URL';

  @override
  String get backendBaseUrlLabel => 'Base URL';

  @override
  String get backendTestConnection => 'Test connection';

  @override
  String get backendUrlSaved => 'Backend URL saved.';

  @override
  String backendHealthOk(String version, int latency, String uptime) {
    return 'Connected • v$version • $latency ms • uptime ${uptime}s';
  }

  @override
  String get backendHealthFailedShort => 'Couldn\'t reach the backend.';

  @override
  String get statusAnalyzing => 'Analyzing…';

  @override
  String statusBoardRecognized(Object count) {
    return 'Board recognized ($count pieces)';
  }

  @override
  String get statusComputingMove => 'Computing the best move…';

  @override
  String get statusNoMove => 'No move found';

  @override
  String get statusAnalysisFailed => 'Analysis failed';

  @override
  String get resultTitle => 'Analysis';

  @override
  String get resultIdle => 'No analysis yet. Start one from the Home screen.';

  @override
  String resultErrorCode(String code) {
    return 'Code: $code';
  }

  @override
  String get resultBestMove => 'Best move';

  @override
  String get resultTopMoves => 'Top moves';

  @override
  String get resultExplanation => 'Explanation';

  @override
  String get resultNoExplanation => 'No explanation provided.';

  @override
  String get resultBoard => 'Board';

  @override
  String resultBoardInfo(String side, int count) {
    return '$side to move • $count pieces';
  }

  @override
  String resultFen(String fen) {
    return 'FEN: $fen';
  }

  @override
  String get resultPipeline => 'How it was solved';

  @override
  String get resultScreenshotUnavailable => 'Screenshot preview unavailable';

  @override
  String get resultWarnings => 'Heads-up';

  @override
  String get pipelineVision => 'Board reading';

  @override
  String get pipelineEngine => 'Best move';

  @override
  String get engineOnDevice => 'On-device engine';

  @override
  String get engineCloud => 'Cloud engine';

  @override
  String percentValue(int pct) {
    return '$pct%';
  }

  @override
  String get bestMoveNone => 'No move for this position.';

  @override
  String get labelWxf => 'WXF';

  @override
  String get labelUci => 'UCI';

  @override
  String get labelScore => 'Score';

  @override
  String get labelDepth => 'Depth';

  @override
  String get labelFrom => 'From';

  @override
  String get labelTo => 'To';

  @override
  String get privacyBannerTitle => 'Privacy & AI';

  @override
  String get privacyBannerBody =>
      'To read the board, the screenshot you analyze is sent to OpenAI — through our service, or directly when you use your own API key. Images aren\'t kept on this device unless you turn on history in Settings. Avoid capturing anything private.';

  @override
  String get providersTitle => 'Providers';

  @override
  String get providerAiLabel => 'Board-reading AI';

  @override
  String get providerEngineLabel => 'Move engine';

  @override
  String get sideRed => 'Red';

  @override
  String get sideBlack => 'Black';

  @override
  String get sideUnknown => 'Unknown';

  @override
  String get aiProviderAuto => 'Auto (server default)';

  @override
  String get aiProviderGemini => 'Gemini';

  @override
  String get aiProviderOpenai => 'OpenAI';

  @override
  String get providerMock => 'Test';

  @override
  String get engineProviderStandard => 'Standard';

  @override
  String get aiKeySourceOurs => 'Cloud';

  @override
  String get aiKeySourceOwn => 'My own key';

  @override
  String get engineLocationCloud => 'Cloud';

  @override
  String get engineLocationOnDevice => 'On-device';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAnalysisMode => 'Analysis mode';

  @override
  String get settingsBoardReading => 'Board reading (AI key)';

  @override
  String get settingsOurKeyShort => 'Cloud';

  @override
  String get settingsMyKeyShort => 'My key';

  @override
  String get settingsBoardReadingOwnDesc =>
      'Your own OpenAI key reads the board on this device — usually cheaper, and your key never leaves your phone.';

  @override
  String get settingsBoardReadingOursDesc =>
      'We read the board for you with our OpenAI key.';

  @override
  String get settingsBestMoveEngine => 'Best move (engine)';

  @override
  String get settingsEngineOnDeviceDesc =>
      'The on-device engine is faster, but its move can be weaker or less accurate than our cloud engine.';

  @override
  String get settingsEngineCloudDesc => 'Our cloud engine finds the best move.';

  @override
  String get settingsDownloadingEngine => 'Downloading the on-device engine…';

  @override
  String settingsDownloadingEnginePct(int pct) {
    return 'Downloading the on-device engine $pct%';
  }

  @override
  String get settingsEngineReady => 'On-device engine ready.';

  @override
  String get settingsRetryDownload => 'Retry download';

  @override
  String costHintOwnOnDevice(int n) {
    return 'Runs on your device — no hints used, unless the on-device engine can\'t solve it and we finish on our cloud (1 hint per $n).';
  }

  @override
  String get costHintOurs => 'Uses our key — 1 hint per analysis.';

  @override
  String costHintOwnCloud(int n) {
    return 'Your key + our cloud engine — 1 hint per $n analyses.';
  }

  @override
  String get settingsApiKeyLabel => 'Your OpenAI API key';

  @override
  String get settingsApiKeyHelp =>
      'Stored only on this device (secure storage); never sent to our backend.';

  @override
  String get settingsSaveKey => 'Save key';

  @override
  String get settingsVisionModelLabel => 'Vision model (OpenAI)';

  @override
  String settingsVisionModelHelp(String model) {
    return 'The OpenAI model that reads the board from your screenshot. Leave it blank to use the recommended model ($model). Avoid gpt-4o-mini — it misreads pieces and produces illegal boards.';
  }

  @override
  String get settingsYourSideDesc =>
      'Pick the side you play. The engine treats this as the side to move, so it always solves for your turn.';

  @override
  String get settingsEngineTuning => 'Engine tuning';

  @override
  String settingsSearchDepth(int value) {
    return 'Search depth: $value';
  }

  @override
  String settingsMoveTime(int value) {
    return 'Move time: $value ms';
  }

  @override
  String settingsTopMoves(int value) {
    return 'Top moves to show: $value';
  }

  @override
  String settingsThreads(int value) {
    return 'Threads: $value';
  }

  @override
  String settingsHash(int value) {
    return 'Hash: $value MB';
  }

  @override
  String get settingsEngineTuningHelp =>
      'Threads and Hash make the engine faster. \"Top moves\" shows several of its best options. For a quicker answer, lower the search depth or move time — it won\'t make the engine play weaker.';

  @override
  String get settingsCaptureArea => 'Capture area';

  @override
  String get settingsCaptureAreaDesc =>
      'By default the whole screen is captured. In Solver Mode you can draw a focus box (e.g. just the board) from the floating button\'s \"Select capture area\", or start it here.';

  @override
  String get settingsSelectArea => 'Select area';

  @override
  String get settingsUseFullScreen => 'Use full screen';

  @override
  String get settingsLanguageCard => 'Language';

  @override
  String get settingsAppLanguage => 'App language';

  @override
  String get settingsMoveNotationLanguage => 'Move-notation language';

  @override
  String get languageSystem => 'System default';

  @override
  String get settingsPrivacy => 'Privacy';

  @override
  String get settingsStoreScreenshots => 'Store screenshots on this device';

  @override
  String get settingsStoreScreenshotsDesc =>
      'Off by default. When on, analyzed images are kept on this device and shown in History.';

  @override
  String settingsStoreScreenshotsOnDesc(int count) {
    return 'Keeping the last $count analyzed screenshots on this device — older ones are removed automatically.';
  }

  @override
  String get settingsPrivacyPolicy => 'Privacy Policy';

  @override
  String get settingsLicenses => 'Open-source licenses';

  @override
  String get settingsDeviceId => 'Device ID';

  @override
  String get settingsEngineSwitchedCloud =>
      'On-device engine unavailable — switched to the Cloud engine.';

  @override
  String get settingsServerSwitchedOwn =>
      'The server is unavailable — switched to your own key + on-device engine.';

  @override
  String get settingsServerAddKey =>
      'The server is unavailable. Add your own OpenAI key to analyze on your device.';

  @override
  String get settingsApiKeySaved => 'API key saved on this device.';

  @override
  String get settingsApiKeyCleared => 'API key cleared.';

  @override
  String get settingsStartSolverFirst =>
      'Start Solver Mode first, then select the capture area.';

  @override
  String get settingsCaptureReset => 'Capture area reset to the full screen.';

  @override
  String get settingsDeviceIdCopied => 'Device ID copied.';

  @override
  String get settingsPrivacyOpenFailed => 'Couldn\'t open the privacy policy.';

  @override
  String get hintsGetMore => 'Get more hints';

  @override
  String hintsBalance(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'You have $count hints.',
      one: 'You have 1 hint.',
    );
    return '$_temp0 Each board analysis on our server uses one hint.';
  }

  @override
  String get hintsWatchAd => 'Watch an ad for +1 hint';

  @override
  String get hintsBuyPack => 'Buy a hint pack';

  @override
  String get hintsPacksUnavailable =>
      'Packs aren\'t available yet — create the products in Play Console (or sign in to the Play Store) to enable purchases.';

  @override
  String hintsPackTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hints',
      one: '1 hint',
    );
    return '$_temp0';
  }

  @override
  String get hintsAdReward => '+1 hint — thanks for watching!';

  @override
  String get hintsNoAdReady => 'No ad is ready yet — please try again shortly.';

  @override
  String get hintsChipTooltip => 'Hints — tap to get more';

  @override
  String get hintsOutOfHints =>
      'You\'re out of hints — watch an ad or buy a pack to keep analyzing.';

  @override
  String get solverStarted => 'Solver Mode started.';

  @override
  String get solverStopped => 'Solver Mode stopped.';

  @override
  String solverScreenshotFailed(String reason) {
    return 'Screenshot failed: $reason';
  }

  @override
  String solverPermissionDenied(String permission) {
    return 'The $permission permission was denied.';
  }

  @override
  String solverSideSet(String side) {
    return 'Playing as $side.';
  }

  @override
  String get solverNeedsPhysicalDevice =>
      'Solver Mode needs a real Android device.';

  @override
  String get solverGrantOverlay =>
      'Allow the overlay permission, then press Start again.';

  @override
  String get solverNeedCapturePermission =>
      'Screen-capture permission is required to start.';

  @override
  String solverFailedStart(String error) {
    return 'Couldn\'t start: $error';
  }

  @override
  String solverFailedStop(String error) {
    return 'Couldn\'t stop: $error';
  }

  @override
  String solverCaptureFailed(String error) {
    return 'Capture failed: $error';
  }

  @override
  String get fallbackOwnKeyVision =>
      'Couldn\'t use your OpenAI key, so we read the board with ours (1 hint).';

  @override
  String fallbackOnDeviceEngine(int n) {
    return 'The on-device engine couldn\'t find a move, so we used our cloud engine (1 hint per $n).';
  }

  @override
  String engineDownloadFailed(String error) {
    return 'Couldn\'t download the on-device engine. $error';
  }

  @override
  String get ondeviceMissingApiKey =>
      'Using your own key needs an OpenAI API key. Add it in Settings.';

  @override
  String get ondeviceEngineNotReady =>
      'The on-device engine isn\'t ready, so the best move wasn\'t computed. Switch the engine to Cloud in Settings to finish.';

  @override
  String get ondeviceMissingGenerals =>
      'Couldn\'t find both generals, so the best move wasn\'t computed. Try capturing again with a clearer view of the board.';

  @override
  String get ondeviceIllegalPosition =>
      'The board that was read isn\'t a legal Xiangqi position — some pieces landed on impossible squares, so no move was computed. Capture again with a clearer view, or use a stronger Vision model.';

  @override
  String ondeviceEngineFailed(String error) {
    return 'On-device engine failed: $error';
  }

  @override
  String get ondeviceBoardOnly => 'Board recognized. No move was computed.';

  @override
  String get visionMissingKey =>
      'No OpenAI API key set. Add yours in Settings.';

  @override
  String visionNetwork(String detail) {
    return 'Couldn\'t reach OpenAI: $detail.';
  }

  @override
  String visionApiError(int status) {
    return 'OpenAI request failed (HTTP $status).';
  }

  @override
  String get visionApiErrorImageHint =>
      ' The screenshot may be too small, corrupted, or not a real image.';

  @override
  String get visionEmpty => 'OpenAI returned an empty response.';

  @override
  String get visionBadJson =>
      'Couldn\'t read the model\'s response (invalid JSON).';

  @override
  String visionDroppedPieces(int count) {
    return 'Ignored $count unreadable piece(s) from the board reading.';
  }

  @override
  String netConnectTimeout(String url) {
    return 'Connection timed out. Is the backend reachable at $url?';
  }

  @override
  String get netSendTimeout => 'Upload timed out. Try a smaller image.';

  @override
  String get netReceiveTimeout => 'The server took too long to respond.';

  @override
  String netConnectError(String url) {
    return 'Couldn\'t reach the backend at $url.';
  }

  @override
  String get netBadCert => 'The server\'s certificate is invalid.';

  @override
  String get netCancelled => 'The request was cancelled.';

  @override
  String get netBadResponse => 'The server returned an unexpected response.';

  @override
  String get netUnknown => 'An unknown network error occurred.';

  @override
  String apiFileNotFound(String path) {
    return 'Screenshot file not found at $path.';
  }

  @override
  String get apiFileTooLarge =>
      'The image is larger than the 8 MB upload limit.';

  @override
  String get apiMissingData => 'The server response is missing its data.';

  @override
  String get apiParseError => 'Couldn\'t read the server response.';

  @override
  String get apiServerError => 'The server reported an error.';

  @override
  String apiServerHttpError(String code) {
    return 'The server returned an error (HTTP $code).';
  }

  @override
  String apiHealthFailed(int code) {
    return 'Health check failed (HTTP $code).';
  }

  @override
  String apiParseContext(String context, String type) {
    return 'Expected a JSON object for $context but got $type.';
  }

  @override
  String ondeviceVisionFailed(String error) {
    return 'On-device board reading failed: $error';
  }

  @override
  String get billingPackUnavailable => 'That pack isn\'t available right now.';

  @override
  String get billingPurchaseFailed => 'Purchase failed.';

  @override
  String get historyTitle => 'History';

  @override
  String get historyClear => 'Clear history';

  @override
  String get historyClearTitle => 'Clear history?';

  @override
  String get historyClearBody =>
      'This removes all analysis records stored on this device.';

  @override
  String get historyNoMove => 'No move';

  @override
  String get historyEmptyTitle => 'No history yet';

  @override
  String get historyEmptyBody =>
      'Analyses you run appear here as local details (time, provider, best move, confidence).';

  @override
  String get historyAnalysisId => 'Analysis ID';

  @override
  String get historySideToMove => 'Side to move';

  @override
  String get historyBestMoveUci => 'Best move (UCI)';

  @override
  String get historyBestMove => 'Best move';

  @override
  String get historyVisionProvider => 'Board-reading AI';

  @override
  String get historyEngineProvider => 'Move engine';

  @override
  String get historyConfidence => 'Confidence';

  @override
  String get historyScreenshot => 'Screenshot';

  @override
  String get routeNotFound => 'Not found';

  @override
  String routeNoRoute(String uri) {
    return 'No screen for $uri';
  }

  @override
  String get adminSettingsEntry => 'Admin';

  @override
  String get adminTitle => 'Admin';

  @override
  String get adminLock => 'Lock';

  @override
  String get adminUnlock => 'Unlock';

  @override
  String get adminUnlockTitle => 'Admin access';

  @override
  String get adminSecretLabel => 'Admin secret';

  @override
  String get adminSecretHelp => 'Enter the admin secret to manage the server.';

  @override
  String get adminWrongSecret => 'Wrong admin secret.';

  @override
  String adminLoadFailed(String error) {
    return 'Couldn\'t load: $error';
  }

  @override
  String get adminMenuConfig => 'Remote config';

  @override
  String get adminMenuConfigDesc =>
      'Edit the server-driven settings every user gets.';

  @override
  String get adminMenuGrants => 'Hint grants';

  @override
  String get adminMenuGrantsDesc => 'Set starting hint balances by device.';

  @override
  String get adminMenuInstalls => 'Install ledger';

  @override
  String get adminMenuInstallsDesc =>
      'Devices that have claimed their starter hints.';

  @override
  String get adminConfigTitle => 'Remote config';

  @override
  String get adminConfigSave => 'Save';

  @override
  String get adminConfigSaved =>
      'Saved. Users get the change when they reopen the app.';

  @override
  String get adminConfigReset => 'Reset to defaults';

  @override
  String get adminConfigResetConfirm =>
      'Reset all values to the server defaults?';

  @override
  String get adminConfigResetDone => 'Reset to server defaults.';

  @override
  String get adminConfigOverridden => 'Custom (overriding server defaults)';

  @override
  String get adminConfigDefaults => 'Using server defaults';

  @override
  String get adminConfigApplyNote =>
      'Changes take effect when users close and reopen the app.';

  @override
  String get adminCfgGroupAds => 'Ads';

  @override
  String get adminCfgGroupHints => 'Hints';

  @override
  String get adminCfgGroupOnDevice => 'On-device engine';

  @override
  String get adminCfgGroupHistory => 'History';

  @override
  String get adminCfgGroupUi => 'Settings visibility';

  @override
  String get adminCfgGroupAppIcon => 'App icon';

  @override
  String get adminCfgRewarded => 'Rewarded ads';

  @override
  String get adminCfgBanner => 'Banner ads';

  @override
  String get adminCfgAppOpen => 'App-open ads';

  @override
  String get adminCfgUseReal => 'Use real ad units';

  @override
  String get adminCfgFreeOnInstall => 'Free hints on install';

  @override
  String get adminCfgOwnKeyDivisor => 'Own-key hint divisor (1 per N)';

  @override
  String get adminCfgOnDeviceEnabled => 'On-device engine enabled';

  @override
  String get adminCfgNetUrl => 'NNUE net URL';

  @override
  String get adminCfgNetBytes => 'NNUE net size (bytes)';

  @override
  String get adminCfgVisionModel => 'On-device vision model';

  @override
  String get adminCfgStoredScreenshots => 'Screenshots kept on device';

  @override
  String get adminCfgUiBackend => 'Show Backend card';

  @override
  String get adminCfgUiProviders => 'Show Providers card';

  @override
  String get adminCfgUiEngineTuning => 'Show Engine tuning';

  @override
  String get adminCfgUiVisionModel => 'Show Vision model field';

  @override
  String get adminCfgUiLicenses => 'Show Licenses entry';

  @override
  String get adminCfgUiDeviceId => 'Show Device ID tile';

  @override
  String get adminCfgIconVariant => 'Icon variant';

  @override
  String get adminAdd => 'Add';

  @override
  String get adminRemove => 'Remove';

  @override
  String adminRemoveConfirm(String id) {
    return 'Remove $id?';
  }

  @override
  String get adminDeviceId => 'Device ID';

  @override
  String get adminGrantHints => 'hints';

  @override
  String get adminGrantsEmpty => 'No grants yet.';

  @override
  String get adminAddGrant => 'Add grant';

  @override
  String get adminEditGrant => 'Edit grant';

  @override
  String get adminGrantSaved => 'Grant saved.';

  @override
  String get adminGrantRemoved => 'Grant removed.';

  @override
  String get adminInstallsEmpty => 'No installs recorded.';

  @override
  String get adminInstallFirstSeen => 'First seen';

  @override
  String get adminAddInstall => 'Add device';

  @override
  String get adminInstallSaved => 'Saved.';

  @override
  String get adminInstallRemoved => 'Removed.';
}
