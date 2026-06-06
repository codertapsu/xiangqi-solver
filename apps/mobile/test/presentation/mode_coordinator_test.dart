import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiangqi_solver/core/errors/failure.dart';
import 'package:xiangqi_solver/core/network/api_result.dart';
import 'package:xiangqi_solver/core/network/dio_client.dart';
import 'package:xiangqi_solver/features/solver/data/analysis_api.dart';
import 'package:xiangqi_solver/features/solver/data/analysis_repository.dart';
import 'package:xiangqi_solver/features/solver/domain/solver_enums.dart';
import 'package:xiangqi_solver/features/solver/presentation/providers/solver_providers.dart';

/// A repository whose health check we control, without any network.
class _FakeRepo extends AnalysisRepository {
  _FakeRepo({required this.healthy}) : super(AnalysisApi(DioClient()));
  final bool healthy;

  @override
  Future<ApiResult<HealthStatus>> checkHealth() async {
    return healthy
        ? const ApiResult.success(
            HealthStatus(
              status: 'ok',
              timestamp: '',
              uptimeSeconds: 0,
              version: '1.0.0',
              latency: Duration.zero,
            ),
          )
        : const ApiResult.failure(NetworkFailure('backend unreachable'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> boot({
    required AiKeySource aiKey,
    required EngineLocation engine,
    required bool healthy,
    required bool hasKey,
  }) async {
    SharedPreferences.setMockInitialValues({
      'settings.aiKeySource': aiKey.wireValue,
      'settings.engineLocation': engine.wireValue,
    });
    FlutterSecureStorage.setMockInitialValues(
      hasKey ? {'secure.openaiApiKey': 'sk-test'} : {},
    );
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        analysisRepositoryProvider.overrideWithValue(_FakeRepo(healthy: healthy)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('backend-using combo + healthy → ready, unchanged', () async {
    final c = await boot(
      aiKey: AiKeySource.ours,
      engine: EngineLocation.cloud,
      healthy: true,
      hasKey: false,
    );
    final outcome = await c.read(modeCoordinatorProvider).ensureUsableMode();
    expect(outcome, ModeCheckOutcome.ready);
    expect(c.read(settingsProvider).aiKeySource, AiKeySource.ours);
    expect(c.read(settingsProvider).engineLocation, EngineLocation.cloud);
  });

  test('backend down + has key → switches to fully-local', () async {
    final c = await boot(
      aiKey: AiKeySource.ours,
      engine: EngineLocation.cloud,
      healthy: false,
      hasKey: true,
    );
    final outcome = await c.read(modeCoordinatorProvider).ensureUsableMode();
    expect(outcome, ModeCheckOutcome.switchedToOnDevice);
    final s = c.read(settingsProvider);
    expect(s.aiKeySource, AiKeySource.own);
    expect(s.engineLocation, EngineLocation.onDevice);
    expect(s.isFullyLocal, isTrue);
  });

  test('backend down + no key → no mode available, unchanged', () async {
    final c = await boot(
      aiKey: AiKeySource.ours,
      engine: EngineLocation.cloud,
      healthy: false,
      hasKey: false,
    );
    final outcome = await c.read(modeCoordinatorProvider).ensureUsableMode();
    expect(outcome, ModeCheckOutcome.noModeAvailable);
    expect(c.read(settingsProvider).aiKeySource, AiKeySource.ours);
  });

  test('fully-local is always ready and never pings the backend', () async {
    final c = await boot(
      aiKey: AiKeySource.own,
      engine: EngineLocation.onDevice,
      healthy: false,
      hasKey: false,
    );
    final outcome = await c.read(modeCoordinatorProvider).ensureUsableMode();
    expect(outcome, ModeCheckOutcome.ready);
    expect(c.read(settingsProvider).isFullyLocal, isTrue);
  });
}
