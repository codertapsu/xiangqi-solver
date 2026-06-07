import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiangqi_solver/features/monetization/data/billing_service.dart';
import 'package:xiangqi_solver/features/monetization/presentation/wallet_providers.dart';
import 'package:xiangqi_solver/features/solver/presentation/providers/solver_providers.dart';

import '../support/hint_grant_test_override.dart';
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
    Override? hintGrant,
  }) async {
    SharedPreferences.setMockInitialValues(seed);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        billingServiceProvider.overrideWithValue(_FakeBilling()),
        remoteConfig ?? remoteConfigTestOverride,
        hintGrant ?? hintGrantOverride(grant: 10),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('seeds the backend install-grant amount on first launch', () async {
    final c = await boot(hintGrant: hintGrantOverride(grant: 1000));
    c.read(walletProvider); // construct → kicks off the async first-launch seed
    await pumpEventQueue();
    expect(c.read(walletProvider), 1000);
  });

  test('a returning device gets 0 (no re-grant on reinstall)', () async {
    final c = await boot(hintGrant: hintGrantOverride(grant: 0));
    c.read(walletProvider);
    await pumpEventQueue();
    expect(c.read(walletProvider), 0);
  });

  test('offline first launch banks nothing and stays unseeded (retries next launch)', () async {
    final c = await boot(hintGrant: hintGrantOfflineOverride());
    c.read(walletProvider);
    await pumpEventQueue();
    // No free hints banked offline (would let an airplane-mode reinstall farm),
    // and not marked seeded, so a later online launch re-claims.
    expect(c.read(walletProvider), 0);
    expect((await SharedPreferences.getInstance()).getBool('hints.seeded'), isNull);
  });

  test('a credit landing during the install claim is not clobbered by the seed', () async {
    final pending = Completer<int>();
    final c = await boot(hintGrant: hintGrantPendingOverride(pending.future));
    final w = c.read(walletProvider.notifier);
    await pumpEventQueue(); // _load suspends on the in-flight claim
    w.add(5); // a purchase / ad reward credits while the claim is still pending
    expect(c.read(walletProvider), 5);
    pending.complete(10); // claim resolves with a grant of 10
    await pumpEventQueue();
    expect(c.read(walletProvider), 15, reason: '10 granted + 5 credited mid-claim');
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
