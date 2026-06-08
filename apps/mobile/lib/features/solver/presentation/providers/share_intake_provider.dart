import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../../../core/utils/logger.dart';

/// iOS "share a board screenshot into the app" intake.
///
/// iOS forbids both an overlay over other apps and on-demand cross-app screen
/// capture, so Android's Solver Mode has no iOS equivalent. Instead the user
/// screenshots their Xiangqi game in another app and SHARES it into us via a
/// native Share Extension (`ios/ShareExtension`), which drops the image into the
/// shared App Group container and deep-links back here. This service surfaces
/// those shared image paths as a stream; the app shell listens and runs the
/// SAME `AnalysisNotifier.analyzeScreenshot(File)` pipeline used everywhere else.
///
/// On every non-iOS host (Android, desktop, web, tests) this is an inert no-op:
/// no plugin calls are made and the stream simply never emits.
class ShareIntake {
  ShareIntake() {
    unawaited(_init());
  }

  static const AppLogger _log = AppLogger('ShareIntake');

  final StreamController<String> _paths = StreamController<String>.broadcast();
  StreamSubscription<List<SharedMediaFile>>? _sub;

  /// The most recently emitted path, used to drop the cold-start + warm-stream
  /// double-delivery the plugin can produce for a single share (which would
  /// otherwise upload twice and double-charge a hint — the analysis pipeline has
  /// a strict one-call-per-image contract).
  String? _lastEmitted;

  /// Absolute paths of screenshots shared into the app (iOS only). Listened to
  /// by the home shell, which uploads + navigates to the result.
  Stream<String> get imagePaths => _paths.stream;

  bool get _enabled =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _init() async {
    if (!_enabled) return;
    try {
      // Warm: shares that arrive while the app is already running.
      _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
        _onMedia,
        onError: (Object e) => _log.warn('Share stream error: $e'),
      );
      // Cold: the share that launched the app. Consume it exactly once, then
      // reset() so it is not re-delivered on the next getInitialMedia call.
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      _onMedia(initial);
      await ReceiveSharingIntent.instance.reset();
    } catch (e) {
      _log.warn('Share intake init failed: $e');
    }
  }

  void _onMedia(List<SharedMediaFile> files) {
    for (final f in files) {
      if (f.type == SharedMediaType.image && f.path.isNotEmpty) {
        _emit(f.path);
        break; // one board per share
      }
    }
  }

  void _emit(String path) {
    if (path == _lastEmitted) return; // dedupe cold+warm re-delivery
    _lastEmitted = path;
    if (!_paths.isClosed) _paths.add(path);
  }

  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_paths.close());
  }
}

/// App-wide share intake. Constructed once; inert off iOS.
final shareIntakeProvider = Provider<ShareIntake>((ref) {
  final intake = ShareIntake();
  ref.onDispose(intake.dispose);
  return intake;
});
