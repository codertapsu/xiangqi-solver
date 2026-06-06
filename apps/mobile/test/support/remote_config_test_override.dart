import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xiangqi_solver/core/remote_config/remote_config.dart';
import 'package:xiangqi_solver/core/remote_config/remote_config_provider.dart';

/// A [RemoteConfigNotifier] that never hits the network, so widget tests don't
/// leave a pending dio timer. Seeds from cache/defaults like the real one.
class StaticRemoteConfigNotifier extends RemoteConfigNotifier {
  // Not a super-parameter: the base ctor's field is private (`_ref`).
  // ignore: use_super_parameters
  StaticRemoteConfigNotifier(Ref ref) : super(ref);

  @override
  Future<void> refresh() async {}
}

/// Drop this into a `ProviderScope(overrides: [...])` in any test that pumps a
/// screen which reads `remoteConfigProvider`.
final remoteConfigTestOverride =
    remoteConfigProvider.overrideWith((ref) => StaticRemoteConfigNotifier(ref));

/// Like [StaticRemoteConfigNotifier] but with all optional settings sections
/// (backend / providers / engine tuning / vision model) REVEALED — they are
/// hidden by default, so tests that exercise those sections opt them on.
class UiVisibleRemoteConfigNotifier extends RemoteConfigNotifier {
  // ignore: use_super_parameters
  UiVisibleRemoteConfigNotifier(Ref ref) : super(ref) {
    state = RemoteConfig.defaults.copyWith(
      showBackendSection: true,
      showProvidersSection: true,
      showEngineTuning: true,
      showVisionModel: true,
    );
  }

  @override
  Future<void> refresh() async {}
}

/// Drop into a `ProviderScope` to render the optional sections in a test.
final remoteConfigUiVisibleTestOverride =
    remoteConfigProvider.overrideWith((ref) => UiVisibleRemoteConfigNotifier(ref));

/// A [RemoteConfigNotifier] pinned to a SPECIFIC value (no network), so a test
/// can assert a backend-driven value (e.g. `freeHintsOnInstall`) is applied.
class FixedRemoteConfigNotifier extends RemoteConfigNotifier {
  // ignore: use_super_parameters
  FixedRemoteConfigNotifier(Ref ref, this._value) : super(ref) {
    state = _value;
  }

  final RemoteConfig _value;

  @override
  Future<void> refresh() async {}
}

/// Override `remoteConfigProvider` with a fixed [value] for a test.
Override remoteConfigOverrideWith(RemoteConfig value) =>
    remoteConfigProvider.overrideWith((ref) => FixedRemoteConfigNotifier(ref, value));
