import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_vi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('vi'),
  ];

  /// App name shown in the launcher task switcher and home title (international markets).
  ///
  /// In en, this message translates to:
  /// **'Xiangqi Strategist'**
  String get appTitle;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get actionOpenSettings;

  /// No description provided for @actionStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get actionStart;

  /// No description provided for @actionStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get actionStop;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get actionClear;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionShow.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get actionShow;

  /// No description provided for @actionHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get actionHide;

  /// No description provided for @tooltipHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get tooltipHistory;

  /// No description provided for @tooltipSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tooltipSettings;

  /// No description provided for @homeServerSwitchedOnDevice.
  ///
  /// In en, this message translates to:
  /// **'The server is unavailable — switched to On-device Mode.'**
  String get homeServerSwitchedOnDevice;

  /// No description provided for @homeNoModeTitle.
  ///
  /// In en, this message translates to:
  /// **'No analysis mode available'**
  String get homeNoModeTitle;

  /// No description provided for @homeNoModeBody.
  ///
  /// In en, this message translates to:
  /// **'The server can\'t be reached and On-device Mode isn\'t set up yet.\n\nAdd your own OpenAI API key in Settings to analyze on your device, or try again when the server is back online.'**
  String get homeNoModeBody;

  /// No description provided for @homeImagePickerError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the image picker: {error}'**
  String homeImagePickerError(String error);

  /// No description provided for @homeSolverMode.
  ///
  /// In en, this message translates to:
  /// **'Solver Mode'**
  String get homeSolverMode;

  /// No description provided for @homeSolverModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Opens a floating button and screen capture so you can analyze the board inside any app.'**
  String get homeSolverModeDesc;

  /// No description provided for @homeSolverModeUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Solver Mode needs a real Android device. Everything else still works here for testing.'**
  String get homeSolverModeUnsupported;

  /// No description provided for @homeYourSide.
  ///
  /// In en, this message translates to:
  /// **'Your side'**
  String get homeYourSide;

  /// No description provided for @homeYourSideDesc.
  ///
  /// In en, this message translates to:
  /// **'Whose turn it is when you analyze.'**
  String get homeYourSideDesc;

  /// No description provided for @homeTryMockTitle.
  ///
  /// In en, this message translates to:
  /// **'Try it (test mode)'**
  String get homeTryMockTitle;

  /// No description provided for @homeTryMockDesc.
  ///
  /// In en, this message translates to:
  /// **'Pick an image to run the full upload and analysis flow without screen capture.'**
  String get homeTryMockDesc;

  /// No description provided for @homePickImage.
  ///
  /// In en, this message translates to:
  /// **'Pick an image & analyze (test)'**
  String get homePickImage;

  /// No description provided for @backendTitle.
  ///
  /// In en, this message translates to:
  /// **'Backend'**
  String get backendTitle;

  /// No description provided for @backendUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Backend URL'**
  String get backendUrlLabel;

  /// No description provided for @backendBaseUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get backendBaseUrlLabel;

  /// No description provided for @backendTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get backendTestConnection;

  /// No description provided for @backendUrlSaved.
  ///
  /// In en, this message translates to:
  /// **'Backend URL saved.'**
  String get backendUrlSaved;

  /// No description provided for @backendHealthOk.
  ///
  /// In en, this message translates to:
  /// **'Connected • v{version} • {latency} ms • uptime {uptime}s'**
  String backendHealthOk(String version, int latency, String uptime);

  /// No description provided for @backendHealthFailedShort.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the backend.'**
  String get backendHealthFailedShort;

  /// No description provided for @statusAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing…'**
  String get statusAnalyzing;

  /// No description provided for @statusNoMove.
  ///
  /// In en, this message translates to:
  /// **'No move found'**
  String get statusNoMove;

  /// No description provided for @statusAnalysisFailed.
  ///
  /// In en, this message translates to:
  /// **'Analysis failed'**
  String get statusAnalysisFailed;

  /// No description provided for @resultTitle.
  ///
  /// In en, this message translates to:
  /// **'Analysis'**
  String get resultTitle;

  /// No description provided for @resultIdle.
  ///
  /// In en, this message translates to:
  /// **'No analysis yet. Start one from the Home screen.'**
  String get resultIdle;

  /// No description provided for @resultErrorCode.
  ///
  /// In en, this message translates to:
  /// **'Code: {code}'**
  String resultErrorCode(String code);

  /// No description provided for @resultBestMove.
  ///
  /// In en, this message translates to:
  /// **'Best move'**
  String get resultBestMove;

  /// No description provided for @resultTopMoves.
  ///
  /// In en, this message translates to:
  /// **'Top moves'**
  String get resultTopMoves;

  /// No description provided for @resultExplanation.
  ///
  /// In en, this message translates to:
  /// **'Explanation'**
  String get resultExplanation;

  /// No description provided for @resultNoExplanation.
  ///
  /// In en, this message translates to:
  /// **'No explanation provided.'**
  String get resultNoExplanation;

  /// No description provided for @resultBoard.
  ///
  /// In en, this message translates to:
  /// **'Board'**
  String get resultBoard;

  /// No description provided for @resultBoardInfo.
  ///
  /// In en, this message translates to:
  /// **'{side} to move • {count} pieces'**
  String resultBoardInfo(String side, int count);

  /// No description provided for @resultFen.
  ///
  /// In en, this message translates to:
  /// **'FEN: {fen}'**
  String resultFen(String fen);

  /// No description provided for @resultPipeline.
  ///
  /// In en, this message translates to:
  /// **'How it was solved'**
  String get resultPipeline;

  /// No description provided for @resultScreenshotUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Screenshot preview unavailable'**
  String get resultScreenshotUnavailable;

  /// No description provided for @resultWarnings.
  ///
  /// In en, this message translates to:
  /// **'Heads-up'**
  String get resultWarnings;

  /// No description provided for @pipelineVision.
  ///
  /// In en, this message translates to:
  /// **'Board reading'**
  String get pipelineVision;

  /// No description provided for @pipelineEngine.
  ///
  /// In en, this message translates to:
  /// **'Best move'**
  String get pipelineEngine;

  /// No description provided for @engineOnDevice.
  ///
  /// In en, this message translates to:
  /// **'On-device engine'**
  String get engineOnDevice;

  /// No description provided for @engineCloud.
  ///
  /// In en, this message translates to:
  /// **'Cloud engine'**
  String get engineCloud;

  /// No description provided for @percentValue.
  ///
  /// In en, this message translates to:
  /// **'{pct}%'**
  String percentValue(int pct);

  /// No description provided for @bestMoveNone.
  ///
  /// In en, this message translates to:
  /// **'No move for this position.'**
  String get bestMoveNone;

  /// No description provided for @labelWxf.
  ///
  /// In en, this message translates to:
  /// **'WXF'**
  String get labelWxf;

  /// No description provided for @labelUci.
  ///
  /// In en, this message translates to:
  /// **'UCI'**
  String get labelUci;

  /// No description provided for @labelScore.
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get labelScore;

  /// No description provided for @labelDepth.
  ///
  /// In en, this message translates to:
  /// **'Depth'**
  String get labelDepth;

  /// No description provided for @labelFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get labelFrom;

  /// No description provided for @labelTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get labelTo;

  /// No description provided for @privacyBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy & AI'**
  String get privacyBannerTitle;

  /// No description provided for @privacyBannerBody.
  ///
  /// In en, this message translates to:
  /// **'To read the board, the screenshot you analyze is sent to OpenAI — through our service, or directly when you use your own API key. Images aren\'t kept on this device unless you turn on history in Settings. Avoid capturing anything private.'**
  String get privacyBannerBody;

  /// No description provided for @providersTitle.
  ///
  /// In en, this message translates to:
  /// **'Providers'**
  String get providersTitle;

  /// No description provided for @providerAiLabel.
  ///
  /// In en, this message translates to:
  /// **'Board-reading AI'**
  String get providerAiLabel;

  /// No description provided for @providerEngineLabel.
  ///
  /// In en, this message translates to:
  /// **'Move engine'**
  String get providerEngineLabel;

  /// No description provided for @sideRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get sideRed;

  /// No description provided for @sideBlack.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get sideBlack;

  /// No description provided for @sideUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get sideUnknown;

  /// No description provided for @aiProviderGemini.
  ///
  /// In en, this message translates to:
  /// **'Gemini'**
  String get aiProviderGemini;

  /// No description provided for @aiProviderOpenai.
  ///
  /// In en, this message translates to:
  /// **'OpenAI'**
  String get aiProviderOpenai;

  /// No description provided for @providerMock.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get providerMock;

  /// No description provided for @engineProviderStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get engineProviderStandard;

  /// No description provided for @aiKeySourceOurs.
  ///
  /// In en, this message translates to:
  /// **'Our key'**
  String get aiKeySourceOurs;

  /// No description provided for @aiKeySourceOwn.
  ///
  /// In en, this message translates to:
  /// **'My own key'**
  String get aiKeySourceOwn;

  /// No description provided for @engineLocationCloud.
  ///
  /// In en, this message translates to:
  /// **'Cloud'**
  String get engineLocationCloud;

  /// No description provided for @engineLocationOnDevice.
  ///
  /// In en, this message translates to:
  /// **'On-device'**
  String get engineLocationOnDevice;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAnalysisMode.
  ///
  /// In en, this message translates to:
  /// **'Analysis mode'**
  String get settingsAnalysisMode;

  /// No description provided for @settingsBoardReading.
  ///
  /// In en, this message translates to:
  /// **'Board reading (AI key)'**
  String get settingsBoardReading;

  /// No description provided for @settingsOurKeyShort.
  ///
  /// In en, this message translates to:
  /// **'Our key'**
  String get settingsOurKeyShort;

  /// No description provided for @settingsMyKeyShort.
  ///
  /// In en, this message translates to:
  /// **'My key'**
  String get settingsMyKeyShort;

  /// No description provided for @settingsBoardReadingOwnDesc.
  ///
  /// In en, this message translates to:
  /// **'Your own OpenAI key reads the board on this device — usually cheaper, and your key never leaves your phone.'**
  String get settingsBoardReadingOwnDesc;

  /// No description provided for @settingsBoardReadingOursDesc.
  ///
  /// In en, this message translates to:
  /// **'We read the board for you with our OpenAI key.'**
  String get settingsBoardReadingOursDesc;

  /// No description provided for @settingsBestMoveEngine.
  ///
  /// In en, this message translates to:
  /// **'Best move (engine)'**
  String get settingsBestMoveEngine;

  /// No description provided for @settingsEngineOnDeviceDesc.
  ///
  /// In en, this message translates to:
  /// **'The on-device engine is faster, but its move can be weaker or less accurate than our cloud engine.'**
  String get settingsEngineOnDeviceDesc;

  /// No description provided for @settingsEngineCloudDesc.
  ///
  /// In en, this message translates to:
  /// **'Our cloud engine finds the best move.'**
  String get settingsEngineCloudDesc;

  /// No description provided for @settingsDownloadingEngine.
  ///
  /// In en, this message translates to:
  /// **'Downloading the on-device engine…'**
  String get settingsDownloadingEngine;

  /// No description provided for @settingsDownloadingEnginePct.
  ///
  /// In en, this message translates to:
  /// **'Downloading the on-device engine {pct}%'**
  String settingsDownloadingEnginePct(int pct);

  /// No description provided for @settingsEngineReady.
  ///
  /// In en, this message translates to:
  /// **'On-device engine ready.'**
  String get settingsEngineReady;

  /// No description provided for @settingsRetryDownload.
  ///
  /// In en, this message translates to:
  /// **'Retry download'**
  String get settingsRetryDownload;

  /// No description provided for @costHintOwnOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Runs on your device — no hints used, unless the on-device engine can\'t solve it and we finish on our cloud (1 hint per {n}).'**
  String costHintOwnOnDevice(int n);

  /// No description provided for @costHintOurs.
  ///
  /// In en, this message translates to:
  /// **'Uses our key — 1 hint per analysis.'**
  String get costHintOurs;

  /// No description provided for @costHintOwnCloud.
  ///
  /// In en, this message translates to:
  /// **'Your key + our cloud engine — 1 hint per {n} analyses.'**
  String costHintOwnCloud(int n);

  /// No description provided for @settingsApiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Your OpenAI API key'**
  String get settingsApiKeyLabel;

  /// No description provided for @settingsApiKeyHelp.
  ///
  /// In en, this message translates to:
  /// **'Stored only on this device (secure storage); never sent to our backend.'**
  String get settingsApiKeyHelp;

  /// No description provided for @settingsSaveKey.
  ///
  /// In en, this message translates to:
  /// **'Save key'**
  String get settingsSaveKey;

  /// No description provided for @settingsVisionModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Vision model (OpenAI)'**
  String get settingsVisionModelLabel;

  /// No description provided for @settingsVisionModelHelp.
  ///
  /// In en, this message translates to:
  /// **'The OpenAI model that reads the board from your screenshot. Leave it blank to use the recommended model ({model}). Avoid gpt-4o-mini — it misreads pieces and produces illegal boards.'**
  String settingsVisionModelHelp(String model);

  /// No description provided for @settingsYourSideDesc.
  ///
  /// In en, this message translates to:
  /// **'Pick the side you play. The engine treats this as the side to move, so it always solves for your turn.'**
  String get settingsYourSideDesc;

  /// No description provided for @settingsEngineTuning.
  ///
  /// In en, this message translates to:
  /// **'Engine tuning'**
  String get settingsEngineTuning;

  /// No description provided for @settingsSearchDepth.
  ///
  /// In en, this message translates to:
  /// **'Search depth: {value}'**
  String settingsSearchDepth(int value);

  /// No description provided for @settingsMoveTime.
  ///
  /// In en, this message translates to:
  /// **'Move time: {value} ms'**
  String settingsMoveTime(int value);

  /// No description provided for @settingsTopMoves.
  ///
  /// In en, this message translates to:
  /// **'Top moves to show: {value}'**
  String settingsTopMoves(int value);

  /// No description provided for @settingsThreads.
  ///
  /// In en, this message translates to:
  /// **'Threads: {value}'**
  String settingsThreads(int value);

  /// No description provided for @settingsHash.
  ///
  /// In en, this message translates to:
  /// **'Hash: {value} MB'**
  String settingsHash(int value);

  /// No description provided for @settingsEngineTuningHelp.
  ///
  /// In en, this message translates to:
  /// **'Threads and Hash make the engine faster. \"Top moves\" shows several of its best options. For a quicker answer, lower the search depth or move time — it won\'t make the engine play weaker.'**
  String get settingsEngineTuningHelp;

  /// No description provided for @settingsCaptureArea.
  ///
  /// In en, this message translates to:
  /// **'Capture area'**
  String get settingsCaptureArea;

  /// No description provided for @settingsCaptureAreaDesc.
  ///
  /// In en, this message translates to:
  /// **'By default the whole screen is captured. In Solver Mode you can draw a focus box (e.g. just the board) from the floating button\'s \"Select capture area\", or start it here.'**
  String get settingsCaptureAreaDesc;

  /// No description provided for @settingsSelectArea.
  ///
  /// In en, this message translates to:
  /// **'Select area'**
  String get settingsSelectArea;

  /// No description provided for @settingsUseFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Use full screen'**
  String get settingsUseFullScreen;

  /// No description provided for @settingsLanguageCard.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageCard;

  /// No description provided for @settingsAppLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get settingsAppLanguage;

  /// No description provided for @settingsMoveNotationLanguage.
  ///
  /// In en, this message translates to:
  /// **'Move-notation language'**
  String get settingsMoveNotationLanguage;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacy;

  /// No description provided for @settingsStoreScreenshots.
  ///
  /// In en, this message translates to:
  /// **'Store screenshots on this device'**
  String get settingsStoreScreenshots;

  /// No description provided for @settingsStoreScreenshotsDesc.
  ///
  /// In en, this message translates to:
  /// **'Off by default. When on, analyzed images are kept on this device and shown in History.'**
  String get settingsStoreScreenshotsDesc;

  /// No description provided for @settingsPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get settingsPrivacyPolicy;

  /// No description provided for @settingsLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get settingsLicenses;

  /// No description provided for @settingsDeviceId.
  ///
  /// In en, this message translates to:
  /// **'Device ID'**
  String get settingsDeviceId;

  /// No description provided for @settingsEngineSwitchedCloud.
  ///
  /// In en, this message translates to:
  /// **'On-device engine unavailable — switched to the Cloud engine.'**
  String get settingsEngineSwitchedCloud;

  /// No description provided for @settingsServerSwitchedOwn.
  ///
  /// In en, this message translates to:
  /// **'The server is unavailable — switched to your own key + on-device engine.'**
  String get settingsServerSwitchedOwn;

  /// No description provided for @settingsServerAddKey.
  ///
  /// In en, this message translates to:
  /// **'The server is unavailable. Add your own OpenAI key to analyze on your device.'**
  String get settingsServerAddKey;

  /// No description provided for @settingsApiKeySaved.
  ///
  /// In en, this message translates to:
  /// **'API key saved on this device.'**
  String get settingsApiKeySaved;

  /// No description provided for @settingsApiKeyCleared.
  ///
  /// In en, this message translates to:
  /// **'API key cleared.'**
  String get settingsApiKeyCleared;

  /// No description provided for @settingsStartSolverFirst.
  ///
  /// In en, this message translates to:
  /// **'Start Solver Mode first, then select the capture area.'**
  String get settingsStartSolverFirst;

  /// No description provided for @settingsCaptureReset.
  ///
  /// In en, this message translates to:
  /// **'Capture area reset to the full screen.'**
  String get settingsCaptureReset;

  /// No description provided for @settingsDeviceIdCopied.
  ///
  /// In en, this message translates to:
  /// **'Device ID copied.'**
  String get settingsDeviceIdCopied;

  /// No description provided for @settingsPrivacyOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the privacy policy.'**
  String get settingsPrivacyOpenFailed;

  /// No description provided for @hintsGetMore.
  ///
  /// In en, this message translates to:
  /// **'Get more hints'**
  String get hintsGetMore;

  /// No description provided for @hintsBalance.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You have 1 hint.} other{You have {count} hints.}} Each board analysis on our server uses one hint.'**
  String hintsBalance(int count);

  /// No description provided for @hintsWatchAd.
  ///
  /// In en, this message translates to:
  /// **'Watch an ad for +1 hint'**
  String get hintsWatchAd;

  /// No description provided for @hintsBuyPack.
  ///
  /// In en, this message translates to:
  /// **'Buy a hint pack'**
  String get hintsBuyPack;

  /// No description provided for @hintsPacksUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Packs aren\'t available yet — create the products in Play Console (or sign in to the Play Store) to enable purchases.'**
  String get hintsPacksUnavailable;

  /// No description provided for @hintsPackTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hint} other{{count} hints}}'**
  String hintsPackTitle(int count);

  /// No description provided for @hintsAdReward.
  ///
  /// In en, this message translates to:
  /// **'+1 hint — thanks for watching!'**
  String get hintsAdReward;

  /// No description provided for @hintsNoAdReady.
  ///
  /// In en, this message translates to:
  /// **'No ad is ready yet — please try again shortly.'**
  String get hintsNoAdReady;

  /// No description provided for @hintsChipTooltip.
  ///
  /// In en, this message translates to:
  /// **'Hints — tap to get more'**
  String get hintsChipTooltip;

  /// No description provided for @hintsOutOfHints.
  ///
  /// In en, this message translates to:
  /// **'You\'re out of hints — watch an ad or buy a pack to keep analyzing.'**
  String get hintsOutOfHints;

  /// No description provided for @solverStarted.
  ///
  /// In en, this message translates to:
  /// **'Solver Mode started.'**
  String get solverStarted;

  /// No description provided for @solverStopped.
  ///
  /// In en, this message translates to:
  /// **'Solver Mode stopped.'**
  String get solverStopped;

  /// No description provided for @solverScreenshotFailed.
  ///
  /// In en, this message translates to:
  /// **'Screenshot failed: {reason}'**
  String solverScreenshotFailed(String reason);

  /// No description provided for @solverPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'The {permission} permission was denied.'**
  String solverPermissionDenied(String permission);

  /// No description provided for @solverSideSet.
  ///
  /// In en, this message translates to:
  /// **'Playing as {side}.'**
  String solverSideSet(String side);

  /// No description provided for @solverNeedsPhysicalDevice.
  ///
  /// In en, this message translates to:
  /// **'Solver Mode needs a real Android device.'**
  String get solverNeedsPhysicalDevice;

  /// No description provided for @solverGrantOverlay.
  ///
  /// In en, this message translates to:
  /// **'Allow the overlay permission, then press Start again.'**
  String get solverGrantOverlay;

  /// No description provided for @solverNeedCapturePermission.
  ///
  /// In en, this message translates to:
  /// **'Screen-capture permission is required to start.'**
  String get solverNeedCapturePermission;

  /// No description provided for @solverFailedStart.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start: {error}'**
  String solverFailedStart(String error);

  /// No description provided for @solverFailedStop.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t stop: {error}'**
  String solverFailedStop(String error);

  /// No description provided for @solverCaptureFailed.
  ///
  /// In en, this message translates to:
  /// **'Capture failed: {error}'**
  String solverCaptureFailed(String error);

  /// No description provided for @fallbackOwnKeyVision.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t use your OpenAI key, so we read the board with ours (1 hint).'**
  String get fallbackOwnKeyVision;

  /// No description provided for @fallbackOnDeviceEngine.
  ///
  /// In en, this message translates to:
  /// **'The on-device engine couldn\'t find a move, so we used our cloud engine (1 hint per {n}).'**
  String fallbackOnDeviceEngine(int n);

  /// No description provided for @engineDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t download the on-device engine. {error}'**
  String engineDownloadFailed(String error);

  /// No description provided for @ondeviceMissingApiKey.
  ///
  /// In en, this message translates to:
  /// **'Using your own key needs an OpenAI API key. Add it in Settings.'**
  String get ondeviceMissingApiKey;

  /// No description provided for @ondeviceEngineNotReady.
  ///
  /// In en, this message translates to:
  /// **'The on-device engine isn\'t ready, so the best move wasn\'t computed. Switch the engine to Cloud in Settings to finish.'**
  String get ondeviceEngineNotReady;

  /// No description provided for @ondeviceMissingGenerals.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find both generals, so the best move wasn\'t computed. Try capturing again with a clearer view of the board.'**
  String get ondeviceMissingGenerals;

  /// No description provided for @ondeviceIllegalPosition.
  ///
  /// In en, this message translates to:
  /// **'The board that was read isn\'t a legal Xiangqi position — some pieces landed on impossible squares, so no move was computed. Capture again with a clearer view, or use a stronger Vision model.'**
  String get ondeviceIllegalPosition;

  /// No description provided for @ondeviceEngineFailed.
  ///
  /// In en, this message translates to:
  /// **'On-device engine failed: {error}'**
  String ondeviceEngineFailed(String error);

  /// No description provided for @ondeviceBoardOnly.
  ///
  /// In en, this message translates to:
  /// **'Board recognized. No move was computed.'**
  String get ondeviceBoardOnly;

  /// No description provided for @visionMissingKey.
  ///
  /// In en, this message translates to:
  /// **'No OpenAI API key set. Add yours in Settings.'**
  String get visionMissingKey;

  /// No description provided for @visionNetwork.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach OpenAI: {detail}.'**
  String visionNetwork(String detail);

  /// No description provided for @visionApiError.
  ///
  /// In en, this message translates to:
  /// **'OpenAI request failed (HTTP {status}).'**
  String visionApiError(int status);

  /// No description provided for @visionApiErrorImageHint.
  ///
  /// In en, this message translates to:
  /// **' The screenshot may be too small, corrupted, or not a real image.'**
  String get visionApiErrorImageHint;

  /// No description provided for @visionEmpty.
  ///
  /// In en, this message translates to:
  /// **'OpenAI returned an empty response.'**
  String get visionEmpty;

  /// No description provided for @visionBadJson.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the model\'s response (invalid JSON).'**
  String get visionBadJson;

  /// No description provided for @visionDroppedPieces.
  ///
  /// In en, this message translates to:
  /// **'Ignored {count} unreadable piece(s) from the board reading.'**
  String visionDroppedPieces(int count);

  /// No description provided for @netConnectTimeout.
  ///
  /// In en, this message translates to:
  /// **'Connection timed out. Is the backend reachable at {url}?'**
  String netConnectTimeout(String url);

  /// No description provided for @netSendTimeout.
  ///
  /// In en, this message translates to:
  /// **'Upload timed out. Try a smaller image.'**
  String get netSendTimeout;

  /// No description provided for @netReceiveTimeout.
  ///
  /// In en, this message translates to:
  /// **'The server took too long to respond.'**
  String get netReceiveTimeout;

  /// No description provided for @netConnectError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the backend at {url}.'**
  String netConnectError(String url);

  /// No description provided for @netBadCert.
  ///
  /// In en, this message translates to:
  /// **'The server\'s certificate is invalid.'**
  String get netBadCert;

  /// No description provided for @netCancelled.
  ///
  /// In en, this message translates to:
  /// **'The request was cancelled.'**
  String get netCancelled;

  /// No description provided for @netBadResponse.
  ///
  /// In en, this message translates to:
  /// **'The server returned an unexpected response.'**
  String get netBadResponse;

  /// No description provided for @netUnknown.
  ///
  /// In en, this message translates to:
  /// **'An unknown network error occurred.'**
  String get netUnknown;

  /// No description provided for @apiFileNotFound.
  ///
  /// In en, this message translates to:
  /// **'Screenshot file not found at {path}.'**
  String apiFileNotFound(String path);

  /// No description provided for @apiFileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The image is larger than the 8 MB upload limit.'**
  String get apiFileTooLarge;

  /// No description provided for @apiMissingData.
  ///
  /// In en, this message translates to:
  /// **'The server response is missing its data.'**
  String get apiMissingData;

  /// No description provided for @apiParseError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the server response.'**
  String get apiParseError;

  /// No description provided for @apiServerError.
  ///
  /// In en, this message translates to:
  /// **'The server reported an error.'**
  String get apiServerError;

  /// No description provided for @apiServerHttpError.
  ///
  /// In en, this message translates to:
  /// **'The server returned an error (HTTP {code}).'**
  String apiServerHttpError(String code);

  /// No description provided for @apiHealthFailed.
  ///
  /// In en, this message translates to:
  /// **'Health check failed (HTTP {code}).'**
  String apiHealthFailed(int code);

  /// No description provided for @apiParseContext.
  ///
  /// In en, this message translates to:
  /// **'Expected a JSON object for {context} but got {type}.'**
  String apiParseContext(String context, String type);

  /// No description provided for @ondeviceVisionFailed.
  ///
  /// In en, this message translates to:
  /// **'On-device board reading failed: {error}'**
  String ondeviceVisionFailed(String error);

  /// No description provided for @billingPackUnavailable.
  ///
  /// In en, this message translates to:
  /// **'That pack isn\'t available right now.'**
  String get billingPackUnavailable;

  /// No description provided for @billingPurchaseFailed.
  ///
  /// In en, this message translates to:
  /// **'Purchase failed.'**
  String get billingPurchaseFailed;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @historyClear.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get historyClear;

  /// No description provided for @historyClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear history?'**
  String get historyClearTitle;

  /// No description provided for @historyClearBody.
  ///
  /// In en, this message translates to:
  /// **'This removes all analysis records stored on this device.'**
  String get historyClearBody;

  /// No description provided for @historyNoMove.
  ///
  /// In en, this message translates to:
  /// **'No move'**
  String get historyNoMove;

  /// No description provided for @historyEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No history yet'**
  String get historyEmptyTitle;

  /// No description provided for @historyEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Analyses you run appear here as local details (time, provider, best move, confidence).'**
  String get historyEmptyBody;

  /// No description provided for @historyAnalysisId.
  ///
  /// In en, this message translates to:
  /// **'Analysis ID'**
  String get historyAnalysisId;

  /// No description provided for @historySideToMove.
  ///
  /// In en, this message translates to:
  /// **'Side to move'**
  String get historySideToMove;

  /// No description provided for @historyBestMoveUci.
  ///
  /// In en, this message translates to:
  /// **'Best move (UCI)'**
  String get historyBestMoveUci;

  /// No description provided for @historyBestMove.
  ///
  /// In en, this message translates to:
  /// **'Best move'**
  String get historyBestMove;

  /// No description provided for @historyVisionProvider.
  ///
  /// In en, this message translates to:
  /// **'Board-reading AI'**
  String get historyVisionProvider;

  /// No description provided for @historyEngineProvider.
  ///
  /// In en, this message translates to:
  /// **'Move engine'**
  String get historyEngineProvider;

  /// No description provided for @historyConfidence.
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get historyConfidence;

  /// No description provided for @historyScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Screenshot'**
  String get historyScreenshot;

  /// No description provided for @routeNotFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get routeNotFound;

  /// No description provided for @routeNoRoute.
  ///
  /// In en, this message translates to:
  /// **'No screen for {uri}'**
  String routeNoRoute(String uri);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'vi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'vi':
      return AppLocalizationsVi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
