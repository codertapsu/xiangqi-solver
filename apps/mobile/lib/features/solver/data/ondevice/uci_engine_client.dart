import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../core/utils/logger.dart';
import '../../domain/board_piece.dart';
import '../../domain/board_state.dart';
import 'local/local_fen.dart';
import 'local/local_uci.dart';
import 'on_device_engine.dart';

/// Drives a UCI Xiangqi engine binary over stdin/stdout. A Dart port of the
/// backend `pikafish-engine.service.ts` handshake + parsing. Spawns the process
/// with an ARGS array (no shell), applies options before `isready`, sends
/// `ucinewgame`/`position`/`go`, and parses `info`/`bestmove` (incl. MultiPV).
///
/// It captures stderr AND watches for early process exit, so a real failure
/// (e.g. the engine can't load its NNUE and exits on `go`) surfaces the engine's
/// own message + exit code instead of a generic "timed out".
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
            '${_tail(out.toString(), err.toString())}',
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
            '${_tail(out.toString(), err.toString())}',
            code: 'ENGINE_TIMEOUT',
          ),
        );
      }
    });

    writeLines(['uci']);

    try {
      final raw = await done.future;
      return _parse(raw, depth);
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

  /// The last few non-empty lines of the engine's output, for diagnostics.
  String _tail(String stdout, String stderr) {
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

  LocalEngineMove _parse(String raw, int requestedDepth) {
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
}

/// [OnDeviceEngine] backed by a bundled Pikafish binary driven via
/// [UciEngineClient]. `isAvailable` is true only when BOTH the binary and the
/// NNUE network are present on disk — a netless engine can't search, so we treat
/// it as unavailable and let the caller fall back to a board-only result.
class ProcessOnDeviceEngine implements OnDeviceEngine {
  ProcessOnDeviceEngine({
    required this.binaryPath,
    this.nnuePath,
    UciEngineClient? client,
  }) : _client = client ?? UciEngineClient();

  final String binaryPath;
  final String? nnuePath;
  final UciEngineClient _client;

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
    final fen = toFen(board.pieces, board.sideToMove);
    return _client.run(
      binaryPath: binaryPath,
      nnuePath: nnuePath,
      fen: fen,
      depth: depth,
      threads: threads,
      hashMb: hashMb,
      multiPv: multiPv,
    );
  }
}
