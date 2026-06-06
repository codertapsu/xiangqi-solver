import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiangqi_solver/features/settings/data/settings_repository.dart';
import 'package:xiangqi_solver/features/solver/domain/solver_enums.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsRepository> buildRepo([
    Map<String, Object> initial = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    return SettingsRepository(prefs);
  }

  group('SettingsRepository', () {
    test('returns defaults when nothing is stored', () async {
      final repo = await buildRepo();
      final settings = repo.load();
      final defaults = AppSettings.defaults();
      expect(settings, defaults);
      expect(settings.storeScreenshots, isFalse);
    });

    test('persists and reloads a full settings round-trip', () async {
      final repo = await buildRepo();
      final updated = AppSettings.defaults().copyWith(
        backendUrl: 'http://192.168.1.50:3000',
        aiKeySource: AiKeySource.own,
        engineLocation: EngineLocation.onDevice,
        aiProvider: AiProvider.openai,
        engineProvider: EngineProvider.pikafish,
        engineDepth: 20,
        engineMoveTimeMs: 5000,
        engineMultiPv: 4,
        engineThreads: 4,
        engineHashMb: 512,
        language: 'vi',
        storeScreenshots: true,
        mySide: SideToMove.black,
        onDeviceVisionModel: 'gpt-5.4',
      );

      await repo.save(updated);
      final reloaded = repo.load();

      expect(reloaded, updated);
      expect(reloaded.onDeviceVisionModel, 'gpt-5.4');
    });

    test('clamps out-of-range engine values on save', () async {
      final repo = await buildRepo();
      await repo.save(
        AppSettings.defaults().copyWith(
          engineDepth: 999,
          engineMoveTimeMs: 1,
        ),
      );
      final reloaded = repo.load();
      expect(reloaded.engineDepth, 30);
      expect(reloaded.engineMoveTimeMs, 50);
    });

    test('falls back to defaults for malformed stored values', () async {
      final repo = await buildRepo({
        'settings.aiProvider': 'not-a-provider',
        'settings.backendUrl': '   ',
        'settings.mySide': 'unknown',
      });
      final settings = repo.load();
      expect(settings.aiProvider, AiProvider.mock);
      expect(settings.backendUrl, AppSettings.defaults().backendUrl);
      // 'unknown' is not a playable side, so it falls back to the default (red).
      expect(settings.mySide, SideToMove.red);
    });
  });
}
