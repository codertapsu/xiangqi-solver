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
    required EngineMode mode,
    required bool healthy,
    required bool hasKey,
  }) async {
    SharedPreferences.setMockInitialValues({'settings.engineMode': mode.wireValue});
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

  test('Cloud + backend healthy → ready, stays Cloud', () async {
    final c = await boot(mode: EngineMode.cloud, healthy: true, hasKey: false);
    final outcome = await c.read(modeCoordinatorProvider).ensureUsableMode();
    expect(outcome, ModeCheckOutcome.ready);
    expect(c.read(settingsProvider).engineMode, EngineMode.cloud);
  });

  test('Cloud + backend down + has key → switches to On-device', () async {
    final c = await boot(mode: EngineMode.cloud, healthy: false, hasKey: true);
    final outcome = await c.read(modeCoordinatorProvider).ensureUsableMode();
    expect(outcome, ModeCheckOutcome.switchedToOnDevice);
    expect(c.read(settingsProvider).engineMode, EngineMode.onDevice);
  });

  test('Cloud + backend down + no key → no mode available, stays Cloud', () async {
    final c = await boot(mode: EngineMode.cloud, healthy: false, hasKey: false);
    final outcome = await c.read(modeCoordinatorProvider).ensureUsableMode();
    expect(outcome, ModeCheckOutcome.noModeAvailable);
    expect(c.read(settingsProvider).engineMode, EngineMode.cloud);
  });

  test('On-device is always ready and never pings the backend', () async {
    // healthy:false would matter only if the backend were consulted.
    final c = await boot(mode: EngineMode.onDevice, healthy: false, hasKey: false);
    final outcome = await c.read(modeCoordinatorProvider).ensureUsableMode();
    expect(outcome, ModeCheckOutcome.ready);
    expect(c.read(settingsProvider).engineMode, EngineMode.onDevice);
  });
}
