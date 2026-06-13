import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../core/utils/logger.dart';
import '../../domain/board_piece.dart';
import '../../domain/board_state.dart';
import 'local/local_fen.dart';
import 'local/local_uci.dart';
import 'on_device_engine.dart';

/// Parse a full UCI search transcript ("info ... / bestmove ...") into a
/// [LocalEngineMove] (incl. MultiPV). Shared by the one-shot [UciEngineClient]
/// and the persistent [WarmUciSession]. A Dart port of the backend
/// `pikafish-engine.service.ts` parsing.
LocalEngineMove parseUciTranscript(String raw, int requestedDepth) {
  final best = RegExp(r'bestmove\s+(\S+)').firstMatch(raw)?.group(1);
  if (best == null || best == '(none)') {
    throw const OnDeviceEngineException(
      'The engine did not return a legal move.',
      code: 'ENGINE_NO_MOVE',
    );
  }
  final ({BoardPosition from, BoardPosition to}) primaryMove;
  try {
    primaryMove = uciToMove(best);
  } catch (_) {
    throw OnDeviceEngineException('Unparseable move "$best".', code: 'ENGINE_BAD_MOVE');
  }

  // Deepest info line per multipv index.
  final byIndex = <int, ({String score, int depth, String moveUci})>{};
  for (final line in raw.split('\n')) {
    if (!line.startsWith('info') || !RegExp(r'\bscore\b').hasMatch(line)) continue;
    final idx =
        int.tryParse(RegExp(r'\bmultipv\s+(\d+)').firstMatch(line)?.group(1) ?? '1') ?? 1;
    final depth =
        int.tryParse(RegExp(r'\bdepth\s+(\d+)').firstMatch(line)?.group(1) ?? '0') ?? 0;
    final moveUci = RegExp(r'\bpv\s+(\S+)').firstMatch(line)?.group(1) ?? '';
    final prev = byIndex[idx];
    if (prev == null || depth >= prev.depth) {
      byIndex[idx] = (score: _scoreFromInfo(line), depth: depth, moveUci: moveUci);
    }
  }

  final candidates = <LocalEngineMove>[];
  for (final i in byIndex.keys.toList()..sort()) {
    final e = byIndex[i]!;
    if (e.moveUci.isEmpty) continue;
    try {
      final ft = uciToMove(e.moveUci);
      candidates.add(LocalEngineMove(
        uci: e.moveUci,
        from: ft.from,
        to: ft.to,
        score: e.score,
        depth: e.depth,
      ));
    } catch (_) {}
  }

  final primary = byIndex[1];
  return LocalEngineMove(
    uci: best,
    from: primaryMove.from,
    to: primaryMove.to,
    score: primary?.score ?? '0.00',
    depth: primary?.depth ?? requestedDepth,
    multipv: candidates.length > 1 ? candidates : const [],
  );
}

String _scoreFromInfo(String line) {
  final cp = RegExp(r'\bscore\s+cp\s+(-?\d+)').firstMatch(line);
  if (cp != null) {
    final pawns = int.parse(cp.group(1)!) / 100;
    return '${pawns >= 0 ? '+' : ''}${pawns.toStringAsFixed(2)}';
  }
  final mate = RegExp(r'\bscore\s+mate\s+(-?\d+)').firstMatch(line);
  if (mate != null) return 'mate ${mate.group(1)}';
  return '0.00';
}

/// The last few non-empty lines of the engine's output, for diagnostics.
String _tailOf(String stdout, String stderr) {
  String pick(String s) => s
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList()
      .reversed
      .take(3)
      .toList()
      .reversed
      .join(' | ');
  final e = pick(stderr);
  final o = pick(stdout);
  final parts = [
    if (e.isNotEmpty) 'stderr: $e',
    if (o.isNotEmpty) 'stdout: $o',
  ];
  if (parts.isEmpty) return 'No engine output was captured.';
  final combined = 'Last engine output — ${parts.join('  ')}';
  return combined.length > 500 ? combined.substring(combined.length - 500) : combined;
}

/// Drives a UCI Xiangqi engine binary over stdin/stdout for a SINGLE query.
/// A Dart port of the backend handshake + parsing. Spawns the process with an
/// ARGS array (no shell), applies options before `isready`, sends
/// `ucinewgame`/`position`/`go`, and parses `info`/`bestmove` (incl. MultiPV).
///
/// It captures stderr AND watches for early process exit, so a real failure
/// (e.g. the engine can't load its NNUE and exits on `go`) surfaces the engine's
/// own message + exit code instead of a generic "timed out".
///
/// Production solves go through [WarmUciSession] instead (the process + ~50 MB
/// NNUE load are paid once and reused); this one-shot client remains for
/// diagnostics and as the reference implementation of the protocol.
class UciEngineClient {
  static const AppLogger _log = AppLogger('OnDeviceEngine');

  Future<LocalEngineMove> run({
    required String binaryPath,
    String? nnuePath,
    required String fen,
    int depth = 12,
    int? threads,
    int? hashMb,
    int? multiPv,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // Pikafish cannot search without a network; refuse rather than hang.
    if (nnuePath == null || nnuePath.isEmpty) {
      throw const OnDeviceEngineException(
        'NNUE network not found; the on-device engine cannot search.',
        code: 'ENGINE_NO_NNUE',
      );
    }

    final Process process;
    try {
      process = await Process.start(
        binaryPath,
        const [],
        workingDirectory: File(binaryPath).parent.path,
      );
    } catch (e) {
      throw OnDeviceEngineException('Could not start the engine: $e', code: 'ENGINE_START');
    }

    final out = StringBuffer();
    final err = StringBuffer();
    final done = Completer<String>();
    var phase = 'uci';

    // Write a batch of commands as ONE write + ONE flush. Never flush while a
    // previous flush is still pending — that throws "StreamSink is bound to a
    // stream", which (swallowed) would silently stall the handshake. Batching
    // per phase keeps the delivery guarantee without overlapping flushes.
    void writeLines(List<String> cmds) {
      try {
        process.stdin.write(cmds.map((c) => '$c\n').join());
        process.stdin.flush().catchError((Object _) {});
      } catch (_) {
        // stdin is closed because the process died — the exitCode handler below
        // surfaces the real cause.
      }
    }

    final sub = process.stdout.transform(utf8.decoder).listen((chunk) {
      out.write(chunk);
      final s = out.toString();
      if (phase == 'uci' && s.contains('uciok')) {
        phase = 'ready';
        writeLines([
          'setoption name EvalFile value $nnuePath',
          'setoption name Threads value ${threads ?? 1}',
          'setoption name Hash value ${hashMb ?? 128}',
          'setoption name MultiPV value ${multiPv ?? 1}',
          'isready',
        ]);
      } else if (phase == 'ready' && s.contains('readyok')) {
        phase = 'search';
        writeLines([
          'ucinewgame',
          'position fen $fen',
          depth > 0 ? 'go depth $depth' : 'go movetime 1000',
        ]);
      } else if (phase == 'search' && RegExp(r'\bbestmove\b').hasMatch(s)) {
        if (!done.isCompleted) done.complete(s);
      }
    }, onError: (Object e) {
      if (!done.isCompleted) {
        done.completeError(
          OnDeviceEngineException('Engine output error: $e', code: 'ENGINE_STREAM'),
        );
      }
    });

    final errSub =
        process.stderr.transform(utf8.decoder).listen(err.write, onError: (Object _) {});

    // If the engine exits before we see a bestmove, that IS the failure — report
    // the exit code plus the engine's own last words rather than waiting out the
    // timeout. (e.g. NNUE load failure: Pikafish prints an error and exit()s.)
    unawaited(process.exitCode.then((code) {
      if (!done.isCompleted) {
        done.completeError(
          OnDeviceEngineException(
            'Engine exited (code $code) during "$phase" before returning a move. '
            '${_tailOf(out.toString(), err.toString())}',
            code: 'ENGINE_EXITED',
          ),
        );
      }
    }));

    // Single timeout guard; all completions funnel through `done`, so late
    // signals are harmless no-ops.
    final timer = Timer(timeout, () {
      if (!done.isCompleted) {
        done.completeError(
          OnDeviceEngineException(
            'Engine timed out after ${timeout.inSeconds}s during "$phase". '
            '${_tailOf(out.toString(), err.toString())}',
            code: 'ENGINE_TIMEOUT',
          ),
        );
      }
    });

    writeLines(['uci']);

    try {
      final raw = await done.future;
      return parseUciTranscript(raw, depth);
    } catch (e) {
      _log.warn('$e');
      rethrow;
    } finally {
      timer.cancel();
      writeLines(['quit']);
      await sub.cancel();
      await errSub.cancel();
      process.kill(ProcessSignal.sigkill);
    }
  }
}

/// Per-search UCI options that may differ between requests.
typedef _SearchOptions = ({int threads, int hashMb, int multiPv});

/// A PERSISTENT engine session: the expensive part (process spawn + ~50 MB
/// NNUE load from flash + hash allocation) happens once; each subsequent
/// search is just option-deltas + `ucinewgame / position / go`. On a mid-range
/// phone this turns a 1-3 s per-solve engine cold start into tens of ms.
///
/// Mirrors the hardening of the backend warm pool:
///  - a killed/dead session is never reused (a late `bestmove` from an aborted
///    search can't answer the next position);
///  - the transcript window is reset before every wait, so stale `readyok` /
///    `bestmove` text can't satisfy a later wait;
///  - stderr is drained into a BOUNDED tail (diagnostics without unbounded
///    growth over a long-lived process);
///  - an idle timer disposes the session after [idleTimeout] so the engine's
///    RAM (net + hash) is released between solving sessions.
///
/// Searches are serialized: a second [search] awaits the first.
class WarmUciSession {
  WarmUciSession({
    required this.binaryPath,
    required this.nnuePath,
    this.idleTimeout = const Duration(minutes: 2),
  });

  static const AppLogger _log = AppLogger('WarmUciSession');
  static const int _maxErrTailChars = 4096;

  final String binaryPath;
  final String nnuePath;
  final Duration idleTimeout;

  Process? _process;
  bool _alive = false;
  String _buffer = '';
  String _errTail = '';
  _SearchOptions? _applied;
  Timer? _idleTimer;
  StreamSubscription<String>? _outSub;
  StreamSubscription<String>? _errSub;

  /// Serializes searches (and disposal) on this session.
  Future<void> _serial = Future<void>.value();

  ({RegExp pattern, Completer<String> completer})? _waiter;

  /// Whether a live engine process is currently attached.
  bool get isWarm => _alive;

  /// Run one search, (re)starting the engine process if needed.
  Future<LocalEngineMove> search({
    required String fen,
    int depth = 12,
    int? threads,
    int? hashMb,
    int? multiPv,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final result = _serial.then((_) => _searchInner(
          fen: fen,
          depth: depth,
          threads: threads ?? 1,
          hashMb: hashMb ?? 128,
          multiPv: multiPv ?? 1,
          timeout: timeout,
        ));
    // Keep the chain alive even when a search fails.
    _serial = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<LocalEngineMove> _searchInner({
    required String fen,
    required int depth,
    required int threads,
    required int hashMb,
    required int multiPv,
    required Duration timeout,
  }) async {
    _idleTimer?.cancel();
    try {
      if (!_alive) await _start(timeout);

      // Apply only the options that changed since the previous search.
      final wanted = (threads: threads, hashMb: hashMb, multiPv: multiPv);
      if (_applied != wanted) {
        final cmds = <String>[
          if (_applied?.threads != threads) 'setoption name Threads value $threads',
          if (_applied?.hashMb != hashMb) 'setoption name Hash value $hashMb',
          if (_applied?.multiPv != multiPv) 'setoption name MultiPV value $multiPv',
          'isready',
        ];
        _buffer = '';
        _send(cmds);
        await _waitFor(RegExp(r'\breadyok\b'), timeout, 'options');
        _applied = wanted;
      }

      _buffer = '';
      _send([
        'ucinewgame',
        'position fen $fen',
        depth > 0 ? 'go depth $depth' : 'go movetime 1000',
      ]);
      final raw = await _waitFor(RegExp(r'\bbestmove\b'), timeout, 'search');
      return parseUciTranscript(raw, depth);
    } catch (e) {
      // Any failure poisons the session: never hand a half-broken process (or
      // a pending late bestmove) to the next search. The next call restarts.
      _log.warn('Warm search failed (session reset): $e');
      _disposeProcess();
      rethrow;
    } finally {
      _armIdleTimer();
    }
  }

  /// Spawn + handshake: uci -> uciok, EvalFile -> readyok (NNUE loads here).
  Future<void> _start(Duration timeout) async {
    if (nnuePath.isEmpty) {
      throw const OnDeviceEngineException(
        'NNUE network not found; the on-device engine cannot search.',
        code: 'ENGINE_NO_NNUE',
      );
    }
    final Process process;
    try {
      process = await Process.start(
        binaryPath,
        const [],
        workingDirectory: File(binaryPath).parent.path,
      );
    } catch (e) {
      throw OnDeviceEngineException('Could not start the engine: $e', code: 'ENGINE_START');
    }
    _process = process;
    _alive = true;
    _buffer = '';
    _errTail = '';
    _applied = null;

    _outSub = process.stdout.transform(utf8.decoder).listen((chunk) {
      _buffer += chunk;
      final w = _waiter;
      if (w != null && w.pattern.hasMatch(_buffer) && !w.completer.isCompleted) {
        _waiter = null;
        w.completer.complete(_buffer);
      }
    }, onError: (Object _) {});

    _errSub = process.stderr.transform(utf8.decoder).listen((chunk) {
      _errTail = (_errTail + chunk);
      if (_errTail.length > _maxErrTailChars) {
        _errTail = _errTail.substring(_errTail.length - _maxErrTailChars);
      }
    }, onError: (Object _) {});

    unawaited(process.exitCode.then((code) {
      if (identical(_process, process)) {
        _alive = false;
        final w = _waiter;
        _waiter = null;
        if (w != null && !w.completer.isCompleted) {
          // Honor a bestmove that made it out before the exit.
          if (RegExp(r'\bbestmove\b').hasMatch(_buffer) &&
              w.pattern.hasMatch(_buffer)) {
            w.completer.complete(_buffer);
          } else {
            w.completer.completeError(OnDeviceEngineException(
              'Engine exited (code $code) before responding. '
              '${_tailOf(_buffer, _errTail)}',
              code: 'ENGINE_EXITED',
            ));
          }
        }
      }
    }));

    _send(['uci']);
    await _waitFor(RegExp(r'\buciok\b'), timeout, 'handshake');
    _buffer = '';
    _send(['setoption name EvalFile value $nnuePath', 'isready']);
    await _waitFor(RegExp(r'\breadyok\b'), timeout, 'network load');
    _buffer = '';
  }

  Future<String> _waitFor(RegExp pattern, Duration timeout, String phase) {
    if (!_alive) {
      return Future.error(const OnDeviceEngineException(
        'The engine process is not running.',
        code: 'ENGINE_EXITED',
      ));
    }
    final completer = Completer<String>();
    _waiter = (pattern: pattern, completer: completer);
    // Immediate check: the match may already be buffered.
    if (pattern.hasMatch(_buffer) && !completer.isCompleted) {
      _waiter = null;
      completer.complete(_buffer);
      return completer.future;
    }
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        _waiter = null;
        completer.completeError(OnDeviceEngineException(
          'Engine timed out after ${timeout.inSeconds}s during "$phase". '
          '${_tailOf(_buffer, _errTail)}',
          code: 'ENGINE_TIMEOUT',
        ));
      }
    });
    return completer.future.whenComplete(timer.cancel);
  }

  void _send(List<String> cmds) {
    final process = _process;
    if (process == null || !_alive) return;
    try {
      process.stdin.write(cmds.map((c) => '$c\n').join());
      process.stdin.flush().catchError((Object _) {});
    } catch (_) {
      // stdin closed — the exitCode handler surfaces the real cause.
    }
  }

  void _armIdleTimer() {
    _idleTimer?.cancel();
    if (!_alive) return;
    _idleTimer = Timer(idleTimeout, _disposeProcess);
  }

  void _disposeProcess() {
    _idleTimer?.cancel();
    final process = _process;
    if (process == null) return;
    // Dead immediately: a disposed session must never satisfy a later wait.
    _alive = false;
    _process = null;
    _applied = null;
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.completer.isCompleted) {
      w.completer.completeError(const OnDeviceEngineException(
        'The engine session was shut down.',
        code: 'ENGINE_EXITED',
      ));
    }
    try {
      process.stdin.write('quit\n');
      process.stdin.flush().catchError((Object _) {});
    } catch (_) {}
    unawaited(_outSub?.cancel());
    unawaited(_errSub?.cancel());
    _outSub = null;
    _errSub = null;
    // Pikafish exits on `quit`; the SIGKILL is the backstop for a hung child.
    Timer(const Duration(milliseconds: 500), () {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {}
    });
  }

  /// Shut the engine down and release its memory. The session can be reused —
  /// the next [search] starts a fresh process.
  void dispose() => _disposeProcess();
}

/// [OnDeviceEngine] backed by a bundled Pikafish binary driven via a
/// persistent [WarmUciSession]. `isAvailable` is true only when BOTH the
/// binary and the NNUE network are present on disk — a netless engine can't
/// search, so we treat it as unavailable and let the caller fall back to a
/// board-only result.
class ProcessOnDeviceEngine implements OnDeviceEngine {
  ProcessOnDeviceEngine({required this.binaryPath, this.nnuePath});

  final String binaryPath;
  final String? nnuePath;
  WarmUciSession? _session;

  @override
  bool get isAvailable {
    if (binaryPath.isEmpty || !File(binaryPath).existsSync()) return false;
    final net = nnuePath;
    if (net == null || net.isEmpty || !File(net).existsSync()) return false;
    return true;
  }

  @override
  Future<LocalEngineMove> bestMove(
    BoardState board, {
    int depth = 12,
    int? threads,
    int? hashMb,
    int? multiPv,
  }) {
    final net = nnuePath;
    if (net == null || net.isEmpty) {
      throw const OnDeviceEngineException(
        'NNUE network not found; the on-device engine cannot search.',
        code: 'ENGINE_NO_NNUE',
      );
    }
    final fen = toFen(board.pieces, board.sideToMove);
    final session = _session ??= WarmUciSession(binaryPath: binaryPath, nnuePath: net);
    return session.search(
      fen: fen,
      depth: depth,
      threads: threads,
      hashMb: hashMb,
      multiPv: multiPv,
    );
  }

  @override
  void dispose() => _session?.dispose();
}
