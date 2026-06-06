import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiangqi_solver/core/remote_config/remote_config.dart';
import 'package:xiangqi_solver/features/monetization/data/billing_service.dart';
import 'package:xiangqi_solver/features/monetization/presentation/wallet_providers.dart';
import 'package:xiangqi_solver/features/solver/presentation/providers/solver_providers.dart';

import '../support/remote_config_test_override.dart';

/// Billing that never touches platform channels, so the device-local wallet can
/// be tested in isolation (the real one wires up Google Play on init).
class _FakeBilling extends BillingService {
  @override
  Future<bool> init(Iterable<String> productIds) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> boot({
    Map<String, Object> seed = const {},
    Override? remoteConfig,
  }) async {
    SharedPreferences.setMockInitialValues(seed);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        billingServiceProvider.overrideWithValue(_FakeBilling()),
        remoteConfig ?? remoteConfigTestOverride,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('seeds the BACKEND free-hints count on first launch', () async {
    final c = await boot(
      remoteConfig: remoteConfigOverrideWith(
        RemoteConfig.defaults.copyWith(freeHintsOnInstall: 1000),
      ),
    );
    c.read(walletProvider); // construct → kicks off the async first-launch seed
    await pumpEventQueue();
    expect(c.read(walletProvider), 1000);
  });

  test('falls back to the default free-hints count when uncached/offline', () async {
    final c = await boot(); // defaults → freeHintsOnInstall = 10
    c.read(walletProvider);
    await pumpEventQueue();
    expect(c.read(walletProvider), RemoteConfig.defaults.freeHintsOnInstall);
  });

  test('does not re-seed when already seeded (keeps the stored balance)', () async {
    final c = await boot(seed: {'hints.seeded': true, 'hints.balance': 2});
    expect(c.read(walletProvider), 2);
  });

  test('spend decrements and clamps at zero; canSpend tracks the balance', () async {
    final c = await boot(seed: {'hints.seeded': true, 'hints.balance': 1});
    final w = c.read(walletProvider.notifier);
    expect(w.canSpend(), isTrue);
    w.spend();
    expect(c.read(walletProvider), 0);
    expect(w.canSpend(), isFalse);
    w.spend(); // clamps — never goes negative
    expect(c.read(walletProvider), 0);
  });

  test('add credits hints', () async {
    final c = await boot(seed: {'hints.seeded': true, 'hints.balance': 0});
    c.read(walletProvider.notifier).add(5);
    expect(c.read(walletProvider), 5);
  });

  test('spendForOwnKey deducts exactly 1 per N analyses (divisor boundary)', () async {
    final c = await boot(seed: {'hints.seeded': true, 'hints.balance': 5});
    final w = c.read(walletProvider.notifier);
    // divisor 3: the first two are free, the third deducts 1.
    w.spendForOwnKey(3);
    expect(c.read(walletProvider), 5, reason: '1st of 3 → no deduct');
    w.spendForOwnKey(3);
    expect(c.read(walletProvider), 5, reason: '2nd of 3 → no deduct');
    w.spendForOwnKey(3);
    expect(c.read(walletProvider), 4, reason: '3rd of 3 → deduct 1');
    // The persisted counter reset, so the next two are free again.
    w.spendForOwnKey(3);
    w.spendForOwnKey(3);
    expect(c.read(walletProvider), 4);
    w.spendForOwnKey(3);
    expect(c.read(walletProvider), 3, reason: '6th call → second deduction');
  });

  test('spendForOwnKey with divisor <= 1 falls back to a full spend', () async {
    final c = await boot(seed: {'hints.seeded': true, 'hints.balance': 3});
    final w = c.read(walletProvider.notifier);
    w.spendForOwnKey(1);
    expect(c.read(walletProvider), 2);
    w.spendForOwnKey(0);
    expect(c.read(walletProvider), 1);
  });

  test('the own-key divisor counter persists (read back from storage each call)', () async {
    // Seed the counter mid-cycle: with divisor 3 and counter already at 2, the
    // very next own-key analysis should deduct.
    final c = await boot(seed: {
      'hints.seeded': true,
      'hints.balance': 5,
      'hints.ownKeyCounter': 2,
    });
    c.read(walletProvider.notifier).spendForOwnKey(3);
    expect(c.read(walletProvider), 4);
  });
}
