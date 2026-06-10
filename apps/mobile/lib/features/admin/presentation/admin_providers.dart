import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../solver/presentation/providers/solver_providers.dart'
    show dioClientProvider, secureKeyStoreProvider;
import '../data/admin_api.dart';

/// The admin API client (shared Dio + secure-storage secret).
final adminApiProvider = Provider<AdminApi>((ref) {
  return AdminApi(ref.watch(dioClientProvider).raw, ref.watch(secureKeyStoreProvider));
});

/// Whether THIS device is an admin — fetched once from `GET /api/admin/status`.
/// Settings watches this to decide whether to show the Admin entry. Resolves to
/// false on any error (offline / not configured), so non-admins never see it.
final adminStatusProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.watch(adminApiProvider).isAdmin();
  } catch (_) {
    return false;
  }
});
