import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiangqi_solver/features/solver/data/ondevice/direct_openai_vision.dart';
import 'package:xiangqi_solver/features/solver/domain/solver_enums.dart';

/// Minimal Dio adapter that returns a canned response (no network).
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responder);
  final ResponseBody Function(RequestOptions options) responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async => responder(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object data) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

DirectOpenAiVisionClient _client(ResponseBody Function(RequestOptions) responder) {
  final dio = Dio()..httpClientAdapter = _FakeAdapter(responder);
  return DirectOpenAiVisionClient(dio: dio);
}

void main() {
  final bytes = Uint8List.fromList([1, 2, 3, 4]);

  test('parses a successful vision response', () async {
    final content = jsonEncode({
      'boardDetected': true,
      'sideToMove': 'red',
      'confidence': 0.92,
      'pieces': [
        {'color': 'red', 'type': 'cannon', 'file': 1, 'rank': 2, 'confidence': 0.95},
        {'color': 'black', 'type': 'king', 'file': 4, 'rank': 9},
      ],
      'warnings': <String>[],
    });
    final client = _client(
      (_) => _json(200, {
        'choices': [
          {
            'message': {'content': content},
          },
        ],
      }),
    );

    final result = await client.extract(
      imageBytes: bytes,
      mimeType: 'image/png',
      apiKey: 'sk-test',
    );

    expect(result.boardDetected, isTrue);
    expect(result.sideToMove, SideToMove.red);
    expect(result.pieces, hasLength(2));
    expect(result.pieces.first.type, PieceType.cannon);
    expect(result.pieces.first.file, 1);
  });

  test('throws a friendly OnDeviceVisionException on image_parse_error', () async {
    final client = _client(
      (_) => _json(400, {
        'error': {
          'message': 'You uploaded an unsupported image.',
          'code': 'image_parse_error',
        },
      }),
    );

    await expectLater(
      client.extract(imageBytes: bytes, mimeType: 'image/png', apiKey: 'sk-test'),
      throwsA(
        isA<OnDeviceVisionException>().having((e) => e.code, 'code', 'image_parse_error'),
      ),
    );
  });

  test('throws MISSING_API_KEY when the key is blank', () async {
    final client = _client((_) => _json(200, const {}));
    await expectLater(
      client.extract(imageBytes: bytes, mimeType: 'image/png', apiKey: '   '),
      throwsA(
        isA<OnDeviceVisionException>().having((e) => e.code, 'code', 'MISSING_API_KEY'),
      ),
    );
  });

  Future<BoardExtraction> extractBoard(Object content) async {
    final client = _client(
      (_) => _json(200, {
        'choices': [
          {
            'message': {'content': jsonEncode(content)},
          },
        ],
      }),
    );
    return client.extract(imageBytes: bytes, mimeType: 'image/png', apiKey: 'sk-test');
  }

  test('rotates a Black-perspective board (Red at top) to canonical coords', () async {
    // Red drawn at the TOP (Black player's view). Kings: red row 0, black row 9.
    final result = await extractBoard({
      'boardDetected': true,
      'redHomeAtTop': true,
      'sideToMove': 'black',
      'confidence': 0.9,
      'pieces': [
        {'color': 'red', 'type': 'king', 'row': 0, 'col': 4},
        {'color': 'black', 'type': 'king', 'row': 9, 'col': 4},
        {'color': 'red', 'type': 'cannon', 'row': 2, 'col': 7},
      ],
      'warnings': <String>[],
    });

    final redKing = result.pieces.firstWhere(
      (p) => p.color == PieceColor.red && p.type == PieceType.king,
    );
    final blackKing = result.pieces.firstWhere(
      (p) => p.color == PieceColor.black && p.type == PieceType.king,
    );
    final cannon = result.pieces.firstWhere((p) => p.type == PieceType.cannon);
    // Red general lands on its home rank 0; black general on rank 9.
    expect([redKing.file, redKing.rank], [4, 0]);
    expect([blackKing.file, blackKing.rank], [4, 9]);
    // cannon row2,col7 -> rank 2, file 8-7 = 1.
    expect([cannon.file, cannon.rank], [1, 2]);
  });

  test('standard board (Red at bottom, row/col) yields the same canonical board', () async {
    final result = await extractBoard({
      'boardDetected': true,
      'sideToMove': 'red',
      'confidence': 0.9,
      'pieces': [
        {'color': 'red', 'type': 'king', 'row': 9, 'col': 4},
        {'color': 'black', 'type': 'king', 'row': 0, 'col': 4},
        {'color': 'red', 'type': 'cannon', 'row': 7, 'col': 1},
      ],
      'warnings': <String>[],
    });

    final redKing = result.pieces.firstWhere(
      (p) => p.color == PieceColor.red && p.type == PieceType.king,
    );
    final cannon = result.pieces.firstWhere((p) => p.type == PieceType.cannon);
    expect([redKing.file, redKing.rank], [4, 0]);
    expect([cannon.file, cannon.rank], [1, 2]);
  });

  test('the kings override a wrong redHomeAtTop flag', () async {
    final result = await extractBoard({
      'boardDetected': true,
      'redHomeAtTop': false, // WRONG — kings show Red is at the top
      'sideToMove': 'black',
      'pieces': [
        {'color': 'red', 'type': 'king', 'row': 0, 'col': 4},
        {'color': 'black', 'type': 'king', 'row': 9, 'col': 4},
      ],
      'warnings': <String>[],
    });
    final redKing = result.pieces.firstWhere(
      (p) => p.color == PieceColor.red && p.type == PieceType.king,
    );
    expect(redKing.rank, 0); // rotated as Red-at-top despite the false flag
  });

  test('drops out-of-range pieces and warns', () async {
    final content = jsonEncode({
      'boardDetected': true,
      'sideToMove': 'unknown',
      'confidence': 0.5,
      'pieces': [
        {'color': 'red', 'type': 'king', 'file': 4, 'rank': 0},
        {'color': 'red', 'type': 'pawn', 'file': 99, 'rank': 3},
      ],
      'warnings': <String>[],
    });
    final client = _client(
      (_) => _json(200, {
        'choices': [
          {
            'message': {'content': content},
          },
        ],
      }),
    );

    final result = await client.extract(
      imageBytes: bytes,
      mimeType: 'image/png',
      apiKey: 'sk-test',
    );
    expect(result.pieces, hasLength(1));
    expect(result.warnings.any((w) => w.contains('malformed')), isTrue);
  });
}
