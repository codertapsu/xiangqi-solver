import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiangqi_solver/core/network/api_result.dart';
import 'package:xiangqi_solver/core/network/dio_client.dart';
import 'package:xiangqi_solver/core/remote_config/remote_config.dart';
import 'package:xiangqi_solver/features/monetization/data/billing_service.dart';
import 'package:xiangqi_solver/features/monetization/presentation/wallet_providers.dart';
import 'package:xiangqi_solver/features/solver/data/analysis_api.dart';
import 'package:xiangqi_solver/features/solver/data/analysis_repository.dart';
import 'package:xiangqi_solver/features/solver/domain/analysis_result.dart';
import 'package:xiangqi_solver/features/solver/domain/board_piece.dart';
import 'package:xiangqi_solver/features/solver/domain/board_state.dart';
import 'package:xiangqi_solver/features/solver/domain/solver_enums.dart';
import 'package:xiangqi_solver/features/solver/presentation/providers/solver_providers.dart';

import '../support/remote_config_test_override.dart';

const _board = BoardState(
  sideToMove: SideToMove.red,
  fen: 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1',
  pieces: <BoardPiece>[],
  confidence: 1,
);

const _result = AnalysisResult(
  analysisId: 't',
  board: _board,
  bestMove: null,
  explanation: '',
  warnings: <String>[],
  engine: ProviderStatus(provider: 'pikafish', ok: true),
  vision: ProviderStatus(provider: 'openai', ok: true),
);

/// Backend repo whose server (our-key) vision + cloud engine both succeed.
class _FakeRepo extends AnalysisRepository {
  _FakeRepo() : super(AnalysisApi(DioClient()));

  int extractCalls = 0;
  int analyzeBoardCalls = 0;

  @override
  Future<ApiResult<({BoardState board, List<String> warnings})>> extractBoard(
    File screenshot, {
    AiProvider? provider,
    SideToMove? sideToMove,
  }) async {
    extractCalls++;
    return const ApiResult.success((board: _board, warnings: <String>[]));
  }

  @override
  Future<ApiResult<AnalysisResult>> analyzeBoard({
    required SideToMove sideToMove,
    required List<BoardPiece> pieces,
    AiProvider? provider,
    String? language,
    EngineOptions options = const EngineOptions(),
  }) async {
    analyzeBoardCalls++;
    return const ApiResult.success(_result);
  }
}

class _FakeBilling extends BillingService {
  @override
  Future<bool> init(Iterable<String> productIds) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'own-key vision fails → fall back to our key → charges exactly 1 FULL hint '
    '(not the 1/N own-key discount)',
    () async {
      // own key + cloud engine, but NO key stored → own-key vision fails.
      SharedPreferences.setMockInitialValues({
        'settings.aiKeySource': AiKeySource.own.wireValue,
        'settings.engineLocation': EngineLocation.cloud.wireValue,
        'hints.seeded': true,
        'hints.balance': 5,
      });
      FlutterSecureStorage.setMockInitialValues({}); // no OpenAI key
      final prefs = await SharedPreferences.getInstance();
      final repo = _FakeRepo();

      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          billingServiceProvider.overrideWithValue(_FakeBilling()),
          analysisRepositoryProvider.overrideWithValue(repo),
          // divisor 3 → IF the discount path were taken, balance would stay 5.
          remoteConfigOverrideWith(
            RemoteConfig.defaults.copyWith(ownKeyHintDivisor: 3),
          ),
        ],
      );
      addTearDown(c.dispose);

      expect(c.read(walletProvider), 5);
      await c
          .read(analysisProvider.notifier)
          .analyzeScreenshot(File('/tmp/none.png'));

      // The fallback used OUR key for vision (+ our cloud engine), so it costs a
      // full hint: 5 → 4. A 1/N charge would have left it at 5.
      expect(c.read(walletProvider), 4);
      expect(repo.extractCalls, 1, reason: 'server vision fallback ran once');
      expect(repo.analyzeBoardCalls, 1, reason: 'cloud engine ran once');
      expect(c.read(analysisProvider), isA<AnalysisSuccess>());
    },
  );
}
