import 'package:flutter_test/flutter_test.dart';
import 'package:xiangqi_solver/core/remote_config/remote_config.dart';

void main() {
  group('RemoteConfig.storedScreenshotsMax', () {
    test('defaults to 5', () {
      expect(RemoteConfig.defaults.storedScreenshotsMax, 5);
    });

    test('parses history.storedScreenshotsMax from /api/config JSON', () {
      final cfg = RemoteConfig.fromJson({
        'history': {'storedScreenshotsMax': 8},
      });
      expect(cfg.storedScreenshotsMax, 8);
    });

    test('falls back to the default when the history group or field is absent', () {
      expect(RemoteConfig.fromJson(const {}).storedScreenshotsMax, 5);
      expect(RemoteConfig.fromJson(const {'history': {}}).storedScreenshotsMax, 5);
    });

    test('round-trips through toJson/fromJson and equality', () {
      final original = RemoteConfig.defaults.copyWith(storedScreenshotsMax: 12);
      final restored = RemoteConfig.fromJson(original.toJson());
      expect(restored.storedScreenshotsMax, 12);
      expect(restored, original);
    });
  });
}
