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
