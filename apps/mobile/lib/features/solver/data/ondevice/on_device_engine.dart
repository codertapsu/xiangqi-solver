import '../../domain/board_piece.dart';
import '../../domain/board_state.dart';

/// Thrown when on-device analysis cannot proceed (engine not bundled, etc.).
class OnDeviceUnavailableException implements Exception {
  const OnDeviceUnavailableException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'OnDeviceUnavailableException($code): $message';
}

/// Thrown when a bundled engine runs but fails (timeout, no move, bad output).
class OnDeviceEngineException implements Exception {
  const OnDeviceEngineException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'OnDeviceEngineException($code): $message';
}

/// One ranked line returned by the local engine (index 0 = best).
class LocalEngineMove {
  const LocalEngineMove({
    required this.uci,
    required this.from,
    required this.to,
    required this.score,
    required this.depth,
    this.multipv = const [],
  });

  final String uci;
  final BoardPosition from;
  final BoardPosition to;
  final String score;
  final int depth;

  /// Ranked candidate lines when MultiPV > 1 (index 0 = best); empty otherwise.
  final List<LocalEngineMove> multipv;
}

/// Seam for a local (on-device) Xiangqi engine — a bundled Pikafish driven over
/// UCI. The analyzer turns the returned [LocalEngineMove] into a localized
/// `BestMove`. See docs/ON_DEVICE_ENGINE.md.
abstract interface class OnDeviceEngine {
  /// `true` only when a real engine + its NNUE are present and runnable.
  bool get isAvailable;

  /// Best move for [board]. Throws [OnDeviceUnavailableException] when no engine
  /// is bundled, or [OnDeviceEngineException] on a runtime failure.
  Future<LocalEngineMove> bestMove(
    BoardState board, {
    int depth,
    int? threads,
    int? hashMb,
    int? multiPv,
  });

  /// Release any warm engine process/memory. Safe to call repeatedly; a later
  /// [bestMove] may start a fresh process.
  void dispose() {}
}

/// Placeholder used until a real engine is bundled/runnable. Keeps the app
/// compiling and the UX honest (reports the mode as unavailable).
class UnavailableOnDeviceEngine implements OnDeviceEngine {
  const UnavailableOnDeviceEngine();

  @override
  bool get isAvailable => false;

  @override
  Future<LocalEngineMove> bestMove(
    BoardState board, {
    int depth = 12,
    int? threads,
    int? hashMb,
    int? multiPv,
  }) {
    throw const OnDeviceUnavailableException(
      'The on-device engine is not available.',
      code: 'ENGINE_NOT_BUNDLED',
    );
  }

  @override
  void dispose() {}
}
