// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get appTitle => 'Quân Sư Cờ Tướng';

  @override
  String get actionRetry => 'Thử lại';

  @override
  String get actionClose => 'Đóng';

  @override
  String get actionOpenSettings => 'Mở Cài đặt';

  @override
  String get actionStart => 'Bắt đầu';

  @override
  String get actionStop => 'Dừng';

  @override
  String get actionSave => 'Lưu';

  @override
  String get actionClear => 'Xóa';

  @override
  String get actionCancel => 'Hủy';

  @override
  String get actionShow => 'Hiện';

  @override
  String get actionHide => 'Ẩn';

  @override
  String get tooltipHistory => 'Lịch sử';

  @override
  String get tooltipSettings => 'Cài đặt';

  @override
  String get homeServerSwitchedOnDevice =>
      'Máy chủ không khả dụng — đã chuyển sang phân tích trên thiết bị.';

  @override
  String get homeNoModeTitle => 'Không có chế độ phân tích nào khả dụng';

  @override
  String get homeNoModeBody =>
      'Không kết nối được máy chủ, và chế độ trên thiết bị thì chưa được thiết lập.\n\nHãy thêm khóa API OpenAI của riêng bạn trong Cài đặt để phân tích ngay trên máy, hoặc thử lại khi máy chủ hoạt động trở lại.';

  @override
  String homeImagePickerError(String error) {
    return 'Không mở được trình chọn ảnh: $error';
  }

  @override
  String get homeSolverMode => 'Chế độ Quân Sư';

  @override
  String get homeSolverModeDesc =>
      'Mở một nút nổi và chụp màn hình để bạn phân tích bàn cờ ngay trong mọi ứng dụng.';

  @override
  String get homeSolverModeUnsupported =>
      'Chế độ Quân Sư cần một thiết bị Android thật. Các phần khác vẫn dùng được ở đây để thử nghiệm.';

  @override
  String get homeYourSide => 'Bên của bạn';

  @override
  String get homeYourSideDesc => 'Đến lượt ai đi khi bạn phân tích.';

  @override
  String get homeTryMockTitle => 'Dùng thử (chế độ thử nghiệm)';

  @override
  String get homeTryMockDesc =>
      'Chọn một ảnh để chạy toàn bộ quy trình tải lên và phân tích mà không cần chụp màn hình.';

  @override
  String get homePickImage => 'Chọn ảnh & phân tích (thử)';

  @override
  String get homeShareInTitle => 'Phân tích ảnh bàn cờ';

  @override
  String get homeShareInDesc =>
      'Chụp màn hình ván cờ trong bất kỳ ứng dụng nào, rồi chia sẻ ảnh vào ứng dụng này — hoặc chọn ảnh bên dưới. Chúng tôi sẽ đọc bàn cờ và chỉ ra nước đi tốt nhất.';

  @override
  String get backendTitle => 'Máy chủ';

  @override
  String get backendUrlLabel => 'Địa chỉ máy chủ';

  @override
  String get backendBaseUrlLabel => 'Địa chỉ gốc';

  @override
  String get backendTestConnection => 'Kiểm tra kết nối';

  @override
  String get backendUrlSaved => 'Đã lưu địa chỉ máy chủ.';

  @override
  String backendHealthOk(String version, int latency, String uptime) {
    return 'Đã kết nối • v$version • $latency ms • hoạt động ${uptime}s';
  }

  @override
  String get backendHealthFailedShort => 'Không kết nối được máy chủ.';

  @override
  String get statusAnalyzing => 'Đang phân tích…';

  @override
  String statusBoardRecognized(Object count) {
    return 'Đã nhận diện bàn cờ ($count quân)';
  }

  @override
  String get statusComputingMove => 'Đang tính nước đi tốt nhất…';

  @override
  String get statusNoMove => 'Không tìm thấy nước đi';

  @override
  String get statusAnalysisFailed => 'Phân tích thất bại';

  @override
  String get resultTitle => 'Phân tích';

  @override
  String get resultIdle =>
      'Chưa có phân tích nào. Hãy bắt đầu từ màn hình Trang chủ.';

  @override
  String resultErrorCode(String code) {
    return 'Mã: $code';
  }

  @override
  String get resultBestMove => 'Nước đi tốt nhất';

  @override
  String get resultTopMoves => 'Các nước hay nhất';

  @override
  String get resultExplanation => 'Giải thích';

  @override
  String get resultNoExplanation => 'Không có giải thích.';

  @override
  String get resultBoard => 'Bàn cờ';

  @override
  String resultBoardInfo(String side, int count) {
    return '$side đi • $count quân';
  }

  @override
  String resultFen(String fen) {
    return 'FEN: $fen';
  }

  @override
  String get resultPipeline => 'Cách giải';

  @override
  String get resultScreenshotUnavailable => 'Không xem được ảnh chụp';

  @override
  String get resultWarnings => 'Lưu ý';

  @override
  String get pipelineVision => 'Đọc bàn cờ';

  @override
  String get pipelineEngine => 'Nước đi tốt nhất';

  @override
  String get engineOnDevice => 'Công cụ trên thiết bị';

  @override
  String get engineCloud => 'Công cụ trên máy chủ';

  @override
  String percentValue(int pct) {
    return '$pct%';
  }

  @override
  String get bestMoveNone => 'Không có nước đi cho thế cờ này.';

  @override
  String get labelWxf => 'WXF';

  @override
  String get labelUci => 'UCI';

  @override
  String get labelScore => 'Điểm';

  @override
  String get labelDepth => 'Độ sâu';

  @override
  String get labelFrom => 'Từ';

  @override
  String get labelTo => 'Đến';

  @override
  String get privacyBannerTitle => 'Quyền riêng tư & AI';

  @override
  String get privacyBannerBody =>
      'Để đọc bàn cờ, ảnh chụp bạn phân tích sẽ được gửi tới OpenAI — qua dịch vụ của chúng tôi, hoặc gửi trực tiếp khi bạn dùng khóa API riêng. Ảnh không được lưu trên máy trừ khi bạn bật Lịch sử trong Cài đặt. Hãy tránh chụp những nội dung riêng tư.';

  @override
  String get providersTitle => 'Nhà cung cấp';

  @override
  String get providerAiLabel => 'AI đọc bàn cờ';

  @override
  String get providerEngineLabel => 'Công cụ tính nước';

  @override
  String get sideRed => 'Đỏ';

  @override
  String get sideBlack => 'Đen';

  @override
  String get sideUnknown => 'Chưa rõ';

  @override
  String get aiProviderAuto => 'Tự động (theo máy chủ)';

  @override
  String get aiProviderGemini => 'Gemini';

  @override
  String get aiProviderOpenai => 'OpenAI';

  @override
  String get providerMock => 'Thử nghiệm';

  @override
  String get engineProviderStandard => 'Tiêu chuẩn';

  @override
  String get aiKeySourceOurs => 'Máy chủ';

  @override
  String get aiKeySourceOwn => 'Khóa của riêng tôi';

  @override
  String get engineLocationCloud => 'Máy chủ';

  @override
  String get engineLocationOnDevice => 'Trên thiết bị';

  @override
  String get settingsTitle => 'Cài đặt';

  @override
  String get settingsAnalysisMode => 'Chế độ phân tích';

  @override
  String get settingsBoardReading => 'Đọc bàn cờ (khóa AI)';

  @override
  String get settingsOurKeyShort => 'Máy chủ';

  @override
  String get settingsMyKeyShort => 'Khóa của tôi';

  @override
  String get settingsBoardReadingOwnDesc =>
      'Khóa OpenAI của riêng bạn sẽ đọc bàn cờ ngay trên máy — thường rẻ hơn, và khóa của bạn không bao giờ rời khỏi điện thoại.';

  @override
  String get settingsBoardReadingOursDesc =>
      'Chúng tôi đọc bàn cờ giúp bạn bằng khóa OpenAI của chúng tôi.';

  @override
  String get settingsBestMoveEngine => 'Nước đi tốt nhất (công cụ)';

  @override
  String get settingsEngineOnDeviceDesc =>
      'Công cụ trên thiết bị nhanh hơn, nhưng nước đi có thể yếu hơn hoặc kém chính xác hơn công cụ trên máy chủ của chúng tôi.';

  @override
  String get settingsEngineCloudDesc =>
      'Công cụ trên máy chủ của chúng tôi sẽ tìm nước đi tốt nhất.';

  @override
  String get settingsDownloadingEngine => 'Đang tải công cụ trên thiết bị…';

  @override
  String settingsDownloadingEnginePct(int pct) {
    return 'Đang tải công cụ trên thiết bị $pct%';
  }

  @override
  String get settingsEngineReady => 'Công cụ trên thiết bị đã sẵn sàng.';

  @override
  String get settingsRetryDownload => 'Tải lại';

  @override
  String costHintOwnOnDevice(int n) {
    return 'Chạy ngay trên máy của bạn — không tốn lượt, trừ khi công cụ trên thiết bị không giải được và chúng tôi hoàn tất trên máy chủ (1 lượt cho mỗi $n).';
  }

  @override
  String get costHintOurs =>
      'Dùng khóa của chúng tôi — 1 lượt cho mỗi lần phân tích.';

  @override
  String costHintOwnCloud(int n) {
    return 'Khóa của bạn + công cụ máy chủ của chúng tôi — 1 lượt cho mỗi $n lần phân tích.';
  }

  @override
  String get settingsApiKeyLabel => 'Khóa API OpenAI của bạn';

  @override
  String get settingsApiKeyHelp =>
      'Chỉ lưu trên thiết bị này (bộ nhớ bảo mật); không bao giờ gửi tới máy chủ của chúng tôi.';

  @override
  String get settingsSaveKey => 'Lưu khóa';

  @override
  String get settingsVisionModelLabel => 'Mô hình đọc bàn cờ (OpenAI)';

  @override
  String settingsVisionModelHelp(String model) {
    return 'Mô hình OpenAI dùng để đọc bàn cờ từ ảnh chụp của bạn. Để trống để dùng mô hình khuyến nghị ($model). Tránh gpt-4o-mini — nó đọc sai quân và tạo ra thế cờ không hợp lệ.';
  }

  @override
  String get settingsYourSideDesc =>
      'Chọn bên bạn đang chơi. Công cụ xem đây là bên tới lượt, nên luôn tính nước cho lượt của bạn.';

  @override
  String get settingsEngineTuning => 'Tinh chỉnh công cụ';

  @override
  String settingsSearchDepth(int value) {
    return 'Độ sâu tìm kiếm: $value';
  }

  @override
  String settingsMoveTime(int value) {
    return 'Thời gian tính: $value ms';
  }

  @override
  String settingsTopMoves(int value) {
    return 'Số nước hay nhất hiển thị: $value';
  }

  @override
  String settingsThreads(int value) {
    return 'Số luồng: $value';
  }

  @override
  String settingsHash(int value) {
    return 'Bộ nhớ đệm: $value MB';
  }

  @override
  String get settingsEngineTuningHelp =>
      'Số luồng và Bộ nhớ đệm giúp công cụ chạy nhanh hơn. \"Số nước hay nhất\" hiển thị nhiều lựa chọn tốt nhất. Muốn có kết quả nhanh hơn, hãy giảm độ sâu tìm kiếm hoặc thời gian tính — việc này không làm công cụ chơi yếu đi.';

  @override
  String get settingsCaptureArea => 'Vùng chụp';

  @override
  String get settingsCaptureAreaDesc =>
      'Mặc định toàn bộ màn hình được chụp. Trong Chế độ Quân Sư, bạn có thể vẽ một khung tập trung (ví dụ chỉ bàn cờ) từ nút nổi qua \"Chọn vùng chụp\", hoặc bắt đầu ngay tại đây.';

  @override
  String get settingsSelectArea => 'Chọn vùng';

  @override
  String get settingsUseFullScreen => 'Dùng toàn màn hình';

  @override
  String get settingsLanguageCard => 'Ngôn ngữ';

  @override
  String get settingsAppLanguage => 'Ngôn ngữ ứng dụng';

  @override
  String get settingsMoveNotationLanguage => 'Ngôn ngữ ghi nước đi';

  @override
  String get languageSystem => 'Theo hệ thống';

  @override
  String get settingsPrivacy => 'Quyền riêng tư';

  @override
  String get settingsStoreScreenshots => 'Lưu ảnh chụp trên thiết bị này';

  @override
  String get settingsStoreScreenshotsDesc =>
      'Mặc định tắt. Khi bật, các ảnh đã phân tích sẽ được giữ trên máy và hiển thị trong Lịch sử.';

  @override
  String settingsStoreScreenshotsOnDesc(int count) {
    return 'Đang giữ $count ảnh phân tích gần nhất trên thiết bị này — các ảnh cũ hơn sẽ tự động bị xóa.';
  }

  @override
  String get settingsPrivacyPolicy => 'Chính sách quyền riêng tư';

  @override
  String get settingsLicenses => 'Giấy phép nguồn mở';

  @override
  String get settingsDeviceId => 'Mã thiết bị';

  @override
  String get settingsEngineSwitchedCloud =>
      'Công cụ trên thiết bị không khả dụng — đã chuyển sang công cụ Máy chủ.';

  @override
  String get settingsServerSwitchedOwn =>
      'Máy chủ không khả dụng — đã chuyển sang khóa của bạn + công cụ trên thiết bị.';

  @override
  String get settingsServerAddKey =>
      'Máy chủ không khả dụng. Hãy thêm khóa OpenAI của bạn để phân tích trên máy.';

  @override
  String get settingsApiKeySaved => 'Đã lưu khóa API trên thiết bị này.';

  @override
  String get settingsApiKeyCleared => 'Đã xóa khóa API.';

  @override
  String get settingsStartSolverFirst =>
      'Hãy bật Chế độ Quân Sư trước, rồi chọn vùng chụp.';

  @override
  String get settingsCaptureReset => 'Đã đặt lại vùng chụp về toàn màn hình.';

  @override
  String get settingsDeviceIdCopied => 'Đã sao chép mã thiết bị.';

  @override
  String get settingsPrivacyOpenFailed =>
      'Không mở được chính sách quyền riêng tư.';

  @override
  String get hintsGetMore => 'Nhận thêm lượt';

  @override
  String hintsBalance(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bạn có $count lượt gợi ý.',
    );
    return '$_temp0 Mỗi lần phân tích bàn cờ trên máy chủ dùng 1 lượt.';
  }

  @override
  String get hintsWatchAd => 'Xem quảng cáo để nhận +1 lượt';

  @override
  String get hintsBuyPack => 'Mua gói lượt gợi ý';

  @override
  String get hintsPacksUnavailable =>
      'Các gói chưa khả dụng — hãy tạo sản phẩm trong Play Console (hoặc đăng nhập Cửa hàng Play) để bật mua hàng.';

  @override
  String hintsPackTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lượt',
    );
    return '$_temp0';
  }

  @override
  String get hintsAdReward => '+1 lượt — cảm ơn bạn đã xem!';

  @override
  String get hintsNoAdReady =>
      'Chưa có quảng cáo nào sẵn sàng — vui lòng thử lại sau giây lát.';

  @override
  String get hintsChipTooltip => 'Lượt gợi ý — chạm để nhận thêm';

  @override
  String get hintsOutOfHints =>
      'Bạn đã hết lượt — xem quảng cáo hoặc mua gói để tiếp tục phân tích.';

  @override
  String get solverStarted => 'Đã bật Chế độ Quân Sư.';

  @override
  String get solverStopped => 'Đã tắt Chế độ Quân Sư.';

  @override
  String solverScreenshotFailed(String reason) {
    return 'Chụp màn hình thất bại: $reason';
  }

  @override
  String solverPermissionDenied(String permission) {
    return 'Quyền $permission đã bị từ chối.';
  }

  @override
  String solverSideSet(String side) {
    return 'Đang chơi bên $side.';
  }

  @override
  String get solverNeedsPhysicalDevice =>
      'Chế độ Quân Sư cần một thiết bị Android thật.';

  @override
  String get solverGrantOverlay =>
      'Hãy cấp quyền hiển thị trên ứng dụng khác, rồi nhấn Bắt đầu lại.';

  @override
  String get solverNeedCapturePermission =>
      'Cần quyền chụp màn hình để bắt đầu.';

  @override
  String solverFailedStart(String error) {
    return 'Không thể bắt đầu: $error';
  }

  @override
  String solverFailedStop(String error) {
    return 'Không thể dừng: $error';
  }

  @override
  String solverCaptureFailed(String error) {
    return 'Chụp thất bại: $error';
  }

  @override
  String get fallbackOwnKeyVision =>
      'Không dùng được khóa OpenAI của bạn, nên chúng tôi đã đọc bàn cờ bằng khóa của mình (1 lượt).';

  @override
  String fallbackOnDeviceEngine(int n) {
    return 'Công cụ trên thiết bị không tìm được nước đi, nên chúng tôi đã dùng công cụ máy chủ (1 lượt cho mỗi $n).';
  }

  @override
  String engineDownloadFailed(String error) {
    return 'Không tải được công cụ trên thiết bị. $error';
  }

  @override
  String get ondeviceMissingApiKey =>
      'Dùng khóa riêng cần có khóa API OpenAI. Hãy thêm trong Cài đặt.';

  @override
  String get ondeviceEngineNotReady =>
      'Công cụ trên thiết bị chưa sẵn sàng, nên chưa tính được nước đi tốt nhất. Chuyển công cụ sang Máy chủ trong Cài đặt để hoàn tất.';

  @override
  String get ondeviceMissingGenerals =>
      'Không tìm thấy đủ hai Tướng, nên chưa tính được nước đi tốt nhất. Hãy chụp lại với góc nhìn rõ hơn về bàn cờ.';

  @override
  String get ondeviceIllegalPosition =>
      'Bàn cờ đọc được không phải thế cờ Tướng hợp lệ — một số quân bị nhận nhầm vào ô không thể có, nên chưa tính được nước đi. Hãy chụp lại rõ hơn, hoặc dùng mô hình đọc bàn cờ mạnh hơn.';

  @override
  String ondeviceEngineFailed(String error) {
    return 'Công cụ trên thiết bị gặp lỗi: $error';
  }

  @override
  String get ondeviceBoardOnly => 'Đã nhận diện bàn cờ. Chưa tính nước đi.';

  @override
  String get visionMissingKey =>
      'Chưa đặt khóa API OpenAI. Hãy thêm khóa của bạn trong Cài đặt.';

  @override
  String visionNetwork(String detail) {
    return 'Không kết nối được OpenAI: $detail.';
  }

  @override
  String visionApiError(int status) {
    return 'Yêu cầu tới OpenAI thất bại (HTTP $status).';
  }

  @override
  String get visionApiErrorImageHint =>
      ' Ảnh chụp có thể quá nhỏ, bị hỏng, hoặc không phải ảnh thật.';

  @override
  String get visionEmpty => 'OpenAI trả về phản hồi rỗng.';

  @override
  String get visionBadJson =>
      'Không đọc được phản hồi của mô hình (JSON không hợp lệ).';

  @override
  String visionDroppedPieces(int count) {
    return 'Đã bỏ qua $count quân không đọc được từ kết quả đọc bàn cờ.';
  }

  @override
  String netConnectTimeout(String url) {
    return 'Hết thời gian kết nối. Máy chủ tại $url có hoạt động không?';
  }

  @override
  String get netSendTimeout => 'Hết thời gian tải lên. Hãy thử ảnh nhỏ hơn.';

  @override
  String get netReceiveTimeout => 'Máy chủ phản hồi quá lâu.';

  @override
  String netConnectError(String url) {
    return 'Không kết nối được máy chủ tại $url.';
  }

  @override
  String get netBadCert => 'Chứng chỉ của máy chủ không hợp lệ.';

  @override
  String get netCancelled => 'Yêu cầu đã bị hủy.';

  @override
  String get netBadResponse => 'Máy chủ trả về phản hồi không mong đợi.';

  @override
  String get netUnknown => 'Đã xảy ra lỗi mạng không xác định.';

  @override
  String apiFileNotFound(String path) {
    return 'Không tìm thấy tệp ảnh tại $path.';
  }

  @override
  String get apiFileTooLarge => 'Ảnh lớn hơn giới hạn tải lên 8 MB.';

  @override
  String get apiMissingData => 'Phản hồi của máy chủ thiếu dữ liệu.';

  @override
  String get apiParseError => 'Không đọc được phản hồi của máy chủ.';

  @override
  String get apiServerError => 'Máy chủ báo lỗi.';

  @override
  String apiServerHttpError(String code) {
    return 'Máy chủ trả về lỗi (HTTP $code).';
  }

  @override
  String apiHealthFailed(int code) {
    return 'Kiểm tra tình trạng thất bại (HTTP $code).';
  }

  @override
  String apiParseContext(String context, String type) {
    return 'Cần một đối tượng JSON cho $context nhưng nhận được $type.';
  }

  @override
  String ondeviceVisionFailed(String error) {
    return 'Đọc bàn cờ trên thiết bị thất bại: $error';
  }

  @override
  String get billingPackUnavailable => 'Gói này hiện chưa khả dụng.';

  @override
  String get billingPurchaseFailed => 'Mua hàng thất bại.';

  @override
  String get historyTitle => 'Lịch sử';

  @override
  String get historyClear => 'Xóa lịch sử';

  @override
  String get historyClearTitle => 'Xóa lịch sử?';

  @override
  String get historyClearBody =>
      'Thao tác này xóa mọi bản ghi phân tích lưu trên thiết bị.';

  @override
  String get historyNoMove => 'Không có nước đi';

  @override
  String get historyEmptyTitle => 'Chưa có lịch sử';

  @override
  String get historyEmptyBody =>
      'Các phân tích bạn chạy sẽ hiện ở đây dưới dạng thông tin cục bộ (thời gian, nhà cung cấp, nước đi tốt nhất, độ tin cậy).';

  @override
  String get historyAnalysisId => 'Mã phân tích';

  @override
  String get historySideToMove => 'Bên tới lượt';

  @override
  String get historyBestMoveUci => 'Nước đi tốt nhất (UCI)';

  @override
  String get historyBestMove => 'Nước đi tốt nhất';

  @override
  String get historyVisionProvider => 'AI đọc bàn cờ';

  @override
  String get historyEngineProvider => 'Công cụ tính nước';

  @override
  String get historyConfidence => 'Độ tin cậy';

  @override
  String get historyScreenshot => 'Ảnh chụp';

  @override
  String get routeNotFound => 'Không tìm thấy';

  @override
  String routeNoRoute(String uri) {
    return 'Không có màn hình cho $uri';
  }

  @override
  String get adminSettingsEntry => 'Quản trị';

  @override
  String get adminTitle => 'Quản trị';

  @override
  String get adminLock => 'Khóa';

  @override
  String get adminUnlock => 'Mở khóa';

  @override
  String get adminUnlockTitle => 'Quyền quản trị';

  @override
  String get adminSecretLabel => 'Mã bí mật quản trị';

  @override
  String get adminSecretHelp => 'Nhập mã bí mật quản trị để quản lý máy chủ.';

  @override
  String get adminWrongSecret => 'Mã bí mật quản trị không đúng.';

  @override
  String adminLoadFailed(String error) {
    return 'Không tải được: $error';
  }

  @override
  String get adminMenuConfig => 'Cấu hình từ xa';

  @override
  String get adminMenuConfigDesc =>
      'Chỉnh các thiết lập do máy chủ điều khiển cho mọi người dùng.';

  @override
  String get adminMenuGrants => 'Cấp lượt';

  @override
  String get adminMenuGrantsDesc => 'Đặt số lượt khởi đầu theo từng thiết bị.';

  @override
  String get adminMenuInstalls => 'Sổ cài đặt';

  @override
  String get adminMenuInstallsDesc => 'Các thiết bị đã nhận lượt khởi đầu.';

  @override
  String get adminConfigTitle => 'Cấu hình từ xa';

  @override
  String get adminConfigSave => 'Lưu';

  @override
  String get adminConfigSaved =>
      'Đã lưu. Người dùng sẽ nhận thay đổi khi mở lại ứng dụng.';

  @override
  String get adminConfigReset => 'Đặt lại mặc định';

  @override
  String get adminConfigResetConfirm =>
      'Đặt lại tất cả về mặc định của máy chủ?';

  @override
  String get adminConfigResetDone => 'Đã đặt lại về mặc định của máy chủ.';

  @override
  String get adminConfigOverridden => 'Tùy chỉnh (ghi đè mặc định máy chủ)';

  @override
  String get adminConfigDefaults => 'Đang dùng mặc định máy chủ';

  @override
  String get adminConfigApplyNote =>
      'Thay đổi có hiệu lực khi người dùng đóng và mở lại ứng dụng.';

  @override
  String get adminCfgGroupAds => 'Quảng cáo';

  @override
  String get adminCfgGroupHints => 'Lượt';

  @override
  String get adminCfgGroupOnDevice => 'Công cụ trên thiết bị';

  @override
  String get adminCfgGroupHistory => 'Lịch sử';

  @override
  String get adminCfgGroupUi => 'Hiển thị mục cài đặt';

  @override
  String get adminCfgGroupAppIcon => 'Biểu tượng ứng dụng';

  @override
  String get adminCfgRewarded => 'Quảng cáo có thưởng';

  @override
  String get adminCfgBanner => 'Quảng cáo biểu ngữ';

  @override
  String get adminCfgAppOpen => 'Quảng cáo khi mở ứng dụng';

  @override
  String get adminCfgUseReal => 'Dùng đơn vị quảng cáo thật';

  @override
  String get adminCfgFreeOnInstall => 'Lượt miễn phí khi cài đặt';

  @override
  String get adminCfgOwnKeyDivisor => 'Mẫu số lượt khi dùng khóa riêng (1/N)';

  @override
  String get adminCfgOnDeviceEnabled => 'Bật công cụ trên thiết bị';

  @override
  String get adminCfgNetUrl => 'URL mạng NNUE';

  @override
  String get adminCfgNetBytes => 'Kích thước mạng NNUE (byte)';

  @override
  String get adminCfgVisionModel => 'Mô hình đọc ảnh trên thiết bị';

  @override
  String get adminCfgStoredScreenshots => 'Số ảnh giữ trên thiết bị';

  @override
  String get adminCfgUiBackend => 'Hiện thẻ Máy chủ';

  @override
  String get adminCfgUiProviders => 'Hiện thẻ Nhà cung cấp';

  @override
  String get adminCfgUiEngineTuning => 'Hiện Tinh chỉnh công cụ';

  @override
  String get adminCfgUiVisionModel => 'Hiện ô Mô hình đọc ảnh';

  @override
  String get adminCfgUiLicenses => 'Hiện mục Giấy phép';

  @override
  String get adminCfgUiDeviceId => 'Hiện ô Mã thiết bị';

  @override
  String get adminCfgIconVariant => 'Biến thể biểu tượng';

  @override
  String get adminAdd => 'Thêm';

  @override
  String get adminRemove => 'Xóa';

  @override
  String adminRemoveConfirm(String id) {
    return 'Xóa $id?';
  }

  @override
  String get adminDeviceId => 'Mã thiết bị';

  @override
  String get adminGrantHints => 'lượt';

  @override
  String get adminGrantsEmpty => 'Chưa có cấp lượt nào.';

  @override
  String get adminAddGrant => 'Thêm cấp lượt';

  @override
  String get adminEditGrant => 'Sửa cấp lượt';

  @override
  String get adminGrantSaved => 'Đã lưu cấp lượt.';

  @override
  String get adminGrantRemoved => 'Đã xóa cấp lượt.';

  @override
  String get adminInstallsEmpty => 'Chưa ghi nhận cài đặt nào.';

  @override
  String get adminInstallFirstSeen => 'Lần đầu thấy';

  @override
  String get adminAddInstall => 'Thêm thiết bị';

  @override
  String get adminInstallSaved => 'Đã lưu.';

  @override
  String get adminInstallRemoved => 'Đã xóa.';
}
