import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xiangqi_solver/core/network/dio_client.dart';
import 'package:xiangqi_solver/features/monetization/data/hint_grant_api.dart';
import 'package:xiangqi_solver/features/monetization/presentation/wallet_providers.dart';

/// A [HintGrantApi] that returns a fixed amount (or throws), or awaits a caller-
/// supplied [pending] future, without hitting the network — for any test that
/// reads `walletProvider` (its first-launch seed claims the install grant).
class FakeHintGrantApi extends HintGrantApi {
  FakeHintGrantApi({this.grant, this.error, this.pending}) : super(DioClient());

  final int? grant;
  final Object? error;

  /// When set, [claim] awaits this — lets a test interleave a credit (purchase/
  /// ad reward) while the install claim is still in flight.
  final Future<int>? pending;

  @override
  Future<int> claim() async {
    if (pending != null) return pending!;
    if (error != null) throw error!;
    return grant ?? 0;
  }
}

/// Override whose claim returns [grant] (no network).
Override hintGrantOverride({int grant = 10}) =>
    hintGrantApiProvider.overrideWithValue(FakeHintGrantApi(grant: grant));

/// Override whose claim THROWS, to exercise the offline (no-grant) path.
Override hintGrantOfflineOverride() => hintGrantApiProvider.overrideWithValue(
  FakeHintGrantApi(error: Exception('offline')),
);

/// Override whose claim awaits [pending], to exercise the in-flight-claim race.
Override hintGrantPendingOverride(Future<int> pending) =>
    hintGrantApiProvider.overrideWithValue(FakeHintGrantApi(pending: pending));
