@TestOn('!windows') // fake engine is a POSIX shell script
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiangqi_solver/features/solver/data/ondevice/on_device_engine.dart';
import 'package:xiangqi_solver/features/solver/data/ondevice/uci_engine_client.dart';
import 'package:xiangqi_solver/features/solver/domain/board_piece.dart';

/// A tiny shell script that mimics Pikafish's UCI handshake so the client can be
/// exercised end-to-end (spawn → handshake → options → search → parse) on the
/// host without the real engine.
const _fakeEngine = '''#!/bin/sh
while IFS= read -r line; do
  case "\$line" in
    uci) echo "id name FakePika"; echo "uciok" ;;
    isready) echo "readyok" ;;
    go*)
      echo "info depth 8 score cp 30 multipv 1 pv b2e2 a9a8"
      echo "info depth 12 score cp 42 multipv 1 pv b2e2 a9a8"
      echo "info depth 12 score cp 18 multipv 2 pv h2e2 a9a8"
      echo "bestmove b2e2 ponder a9a8"
      ;;
    quit) exit 0 ;;
  esac
done
''';

/// A fake engine that fails to load its network and exits on `go` — exactly the
/// production failure mode we need to surface (not mask as a bare timeout).
const _nnueFailEngine = '''#!/bin/sh
while IFS= read -r line; do
  case "\$line" in
    uci) echo "uciok" ;;
    isready) echo "readyok" ;;
    go*)
      echo "info string ERROR: The network was not loaded successfully." 1>&2
      echo "info string The engine will be terminated now." 1>&2
      exit 1
      ;;
    quit) exit 0 ;;
  esac
done
''';

void main() {
  late Directory dir;
  late String nnuePath;

  Future<String> writeEngine(String name, String body) async {
    final file = File('${dir.path}/$name');
    await file.writeAsString(body);
    await Process.run('chmod', ['+x', file.path]);
    return file.path;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('uci_fake');
    // A stand-in net file so the netless guard passes (the fake engine ignores
    // EvalFile; the client only checks the path is non-empty).
    final net = File('${dir.path}/fake.nnue')..writeAsStringSync('not-a-real-net');
    nnuePath = net.path;
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('drives the handshake and parses the best move + MultiPV', () async {
    final enginePath = await writeEngine('fake_engine.sh', _fakeEngine);
    final move = await UciEngineClient().run(
      binaryPath: enginePath,
      nnuePath: nnuePath,
      fen: 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1',
      depth: 12,
      multiPv: 2,
      timeout: const Duration(seconds: 10),
    );

    expect(move.uci, 'b2e2');
    expect(move.from, const BoardPosition(file: 1, rank: 2));
    expect(move.to, const BoardPosition(file: 4, rank: 2));
    expect(move.score, '+0.42');
    expect(move.depth, 12);
    expect(move.multipv, hasLength(2));
    expect(move.multipv.first.uci, 'b2e2');
    expect(move.multipv[1].uci, 'h2e2');
  });

  test('refuses to run without a network (ENGINE_NO_NNUE, no process)', () async {
    final enginePath = await writeEngine('fake_engine.sh', _fakeEngine);
    expect(
      () => UciEngineClient().run(
        binaryPath: enginePath,
        nnuePath: null,
        fen: '9/9/9/9/9/9/9/9/9/9 w - - 0 1',
      ),
      throwsA(isA<OnDeviceEngineException>().having((e) => e.code, 'code', 'ENGINE_NO_NNUE')),
    );
  });

  test('surfaces an engine that exits on `go` with its code + last words', () async {
    final enginePath = await writeEngine('nnue_fail.sh', _nnueFailEngine);
    final stopwatch = Stopwatch()..start();
    Object? caught;
    try {
      await UciEngineClient().run(
        binaryPath: enginePath,
        nnuePath: nnuePath,
        fen: '9/9/9/9/9/9/9/9/9/9 w - - 0 1',
        depth: 12,
        timeout: const Duration(seconds: 10),
      );
      fail('expected an OnDeviceEngineException');
    } catch (e) {
      caught = e;
    }
    stopwatch.stop();

    expect(caught, isA<OnDeviceEngineException>());
    final ex = caught as OnDeviceEngineException;
    expect(ex.code, 'ENGINE_EXITED'); // NOT a generic timeout
    expect(ex.message, contains('code 1'));
    expect(ex.message, contains('terminated now')); // the engine's own message
    // It failed fast, nowhere near the 10s timeout.
    expect(stopwatch.elapsed.inSeconds, lessThan(5));
  });

  test('throws ENGINE_START when the binary does not exist', () async {
    expect(
      () => UciEngineClient().run(
        binaryPath: '${dir.path}/does_not_exist',
        nnuePath: nnuePath,
        fen: '9/9/9/9/9/9/9/9/9/9 w - - 0 1',
      ),
      throwsA(isA<OnDeviceEngineException>().having((e) => e.code, 'code', 'ENGINE_START')),
    );
  });

  group('ProcessOnDeviceEngine.isAvailable', () {
    test('is false without a network path', () async {
      final enginePath = await writeEngine('fake_engine.sh', _fakeEngine);
      final engine = ProcessOnDeviceEngine(binaryPath: enginePath, nnuePath: null);
      expect(engine.isAvailable, isFalse);
    });

    test('is false when the network file is missing', () async {
      final enginePath = await writeEngine('fake_engine.sh', _fakeEngine);
      final engine =
          ProcessOnDeviceEngine(binaryPath: enginePath, nnuePath: '${dir.path}/missing.nnue');
      expect(engine.isAvailable, isFalse);
    });

    test('is true when both the binary and the network exist', () async {
      final enginePath = await writeEngine('fake_engine.sh', _fakeEngine);
      final engine = ProcessOnDeviceEngine(binaryPath: enginePath, nnuePath: nnuePath);
      expect(engine.isAvailable, isTrue);
    });
  });
}
