import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiangqi_solver/core/errors/failure.dart';
import 'package:xiangqi_solver/core/security/secure_key_store.dart';
import 'package:xiangqi_solver/features/solver/data/ondevice/direct_openai_vision.dart';
import 'package:xiangqi_solver/features/solver/data/ondevice/on_device_analyzer.dart';
import 'package:xiangqi_solver/features/solver/data/ondevice/on_device_engine.dart';
import 'package:xiangqi_solver/features/solver/domain/board_piece.dart';
import 'package:xiangqi_solver/features/solver/domain/board_state.dart';
import 'package:xiangqi_solver/features/solver/domain/solver_enums.dart';

/// A fake vision client so the analyzer can be tested without the network.
class _FakeVision implements BoardVisionClient {
  _FakeVision({this.result, this.error});
  final BoardExtraction? result;
  final Object? error;
  String? lastModel;

  @override
  Future<BoardExtraction> extract({
    required Uint8List imageBytes,
    required String mimeType,
    required String apiKey,
    SideToMove? sideToMoveHint,
    String? model,
  }) async {
    lastModel = model;
    if (error != null) throw error!;
    return result!;
  }
}

/// A fake engine that returns a fixed move without spawning a process.
class _FakeEngine implements OnDeviceEngine {
  _FakeEngine(this._move);
  final LocalEngineMove _move;

  @override
  bool get isAvailable => true;

  @override
  Future<LocalEngineMove> bestMove(
    BoardState board, {
    int depth = 12,
    int? threads,
    int? hashMb,
    int? multiPv,
  }) async => _move;
}

/// A fake engine that always fails — used to exercise the analyzer's handling
/// of an engine that rejects the position.
class _ThrowingEngine implements OnDeviceEngine {
  _ThrowingEngine(this._error);
  final OnDeviceEngineException _error;

  @override
  bool get isAvailable => true;

  @override
  Future<LocalEngineMove> bestMove(
    BoardState board, {
    int depth = 12,
    int? threads,
    int? hashMb,
    int? multiPv,
  }) async => throw _error;
}

BoardExtraction _twoKings({List<BoardPiece> extra = const []}) => BoardExtraction(
      boardDetected: true,
      sideToMove: SideToMove.red,
      confidence: 0.9,
      pieces: [
        const BoardPiece(
          color: PieceColor.red,
          type: PieceType.king,
          position: BoardPosition(file: 4, rank: 0),
        ),
        const BoardPiece(
          color: PieceColor.black,
          type: PieceType.king,
          position: BoardPosition(file: 4, rank: 9),
        ),
        ...extra,
      ],
      warnings: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A real 1x1 PNG so analyze()'s readAsBytes succeeds.
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC',
  );
  late File tmp;

  setUp(() {
    tmp = File(
      '${Directory.systemTemp.path}/xq_${DateTime.now().microsecondsSinceEpoch}.png',
    )..writeAsBytesSync(png);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync();
  });

  OnDeviceAnalyzer build(_FakeVision vision) =>
      OnDeviceAnalyzer(SecureKeyStore(), vision);

  const unavailable = UnavailableOnDeviceEngine();

  test('fails with MISSING_API_KEY when no key is stored', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final result = await build(_FakeVision()).analyze(tmp, engine: unavailable);
    expect(result.failureOrNull, isA<OnDeviceFailure>());
    expect(result.failureOrNull?.code, 'MISSING_API_KEY');
  });

  test('recognizes the board but reports the engine is not bundled yet', () async {
    FlutterSecureStorage.setMockInitialValues({'secure.openaiApiKey': 'sk-test'});
    final vision = _FakeVision(
      result: const BoardExtraction(
        boardDetected: true,
        sideToMove: SideToMove.red,
        confidence: 0.9,
        pieces: [
          BoardPiece(
            color: PieceColor.red,
            type: PieceType.king,
            position: BoardPosition(file: 4, rank: 0),
          ),
        ],
        warnings: [],
      ),
    );

    final result = await build(vision).analyze(tmp, engine: unavailable);

    expect(result.isSuccess, isTrue);
    final value = result.valueOrNull!;
    expect(value.bestMove, isNull); // engine not bundled
    expect(value.vision.ok, isTrue); // vision (user's key) succeeded
    expect(value.engine.ok, isFalse);
    expect(value.board.pieces, hasLength(1));
    expect(value.warnings.any((w) => w.toLowerCase().contains('engine')), isTrue);
  });

  test('computes a full localized result when the engine is available', () async {
    FlutterSecureStorage.setMockInitialValues({'secure.openaiApiKey': 'sk-test'});
    final vision = _FakeVision(
      result: const BoardExtraction(
        boardDetected: true,
        sideToMove: SideToMove.red,
        confidence: 0.9,
        pieces: [
          // Both generals present so the move is computed.
          BoardPiece(
            color: PieceColor.red,
            type: PieceType.king,
            position: BoardPosition(file: 4, rank: 0),
          ),
          BoardPiece(
            color: PieceColor.black,
            type: PieceType.king,
            position: BoardPosition(file: 4, rank: 9),
          ),
          // A red cannon that will traverse from file 1 to file 4 (C8=5 / 炮二平五).
          BoardPiece(
            color: PieceColor.red,
            type: PieceType.cannon,
            position: BoardPosition(file: 1, rank: 2),
          ),
        ],
        warnings: [],
      ),
    );
    final engine = _FakeEngine(
      const LocalEngineMove(
        uci: 'b2e2',
        from: BoardPosition(file: 1, rank: 2),
        to: BoardPosition(file: 4, rank: 2),
        score: '+0.42',
        depth: 14,
      ),
    );

    final result = await build(vision)
        .analyze(tmp, engine: engine, language: 'en', visionModel: 'gpt-5.4');

    expect(result.isSuccess, isTrue);
    final value = result.valueOrNull!;
    expect(value.engine.ok, isTrue);
    expect(value.vision.ok, isTrue);
    expect(vision.lastModel, 'gpt-5.4'); // the chosen model is threaded through
    final move = value.bestMove!;
    expect(move.uci, 'b2e2');
    expect(move.notation, 'C8=5'); // WXF: red cannon on file 8 traverses to 5
    expect(move.score, '+0.42');
    expect(move.depth, 14);
  });

  test('explains an illegal board (engine rejects) instead of a raw crash', () async {
    FlutterSecureStorage.setMockInitialValues({'secure.openaiApiKey': 'sk-test'});
    final vision = _FakeVision(result: _twoKings());
    final engine = _ThrowingEngine(
      const OnDeviceEngineException(
        'Engine exited (code 1) during "search" before returning a move. '
        'Last engine output — stdout: ... Unsupported position. '
        'WHITE advisor(s) on invalid positions.',
        code: 'ENGINE_EXITED',
      ),
    );

    final result = await build(vision).analyze(tmp, engine: engine);

    expect(result.isSuccess, isTrue);
    final value = result.valueOrNull!;
    expect(value.bestMove, isNull);
    expect(value.engine.ok, isFalse);
    // Friendly, actionable wording — not the raw "Engine exited (code 1)".
    expect(value.warnings.any((w) => w.contains('legal Xiangqi position')), isTrue);
    expect(value.warnings.any((w) => w.contains('Engine exited')), isFalse);
  });

  test('surfaces a vision error (e.g. bad key) as a failure', () async {
    FlutterSecureStorage.setMockInitialValues({'secure.openaiApiKey': 'sk-bad'});
    final vision = _FakeVision(
      error: const OnDeviceVisionException('Invalid API key', code: 'VISION_API_ERROR'),
    );
    final result = await build(vision).analyze(tmp, engine: unavailable);
    expect(result.failureOrNull?.code, 'VISION_API_ERROR');
  });
}
