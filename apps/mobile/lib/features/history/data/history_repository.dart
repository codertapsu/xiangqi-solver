import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/logger.dart';
import '../domain/history_entry.dart';

/// Persists a bounded list of [HistoryEntry] metadata in [SharedPreferences].
///
/// Stores a JSON array of metadata only — never screenshot bytes. The list is
/// capped at [maxEntries] (most-recent first) to keep storage small.
class HistoryRepository {
  HistoryRepository(this._prefs);

  final SharedPreferences _prefs;
  static const AppLogger _log = AppLogger('HistoryRepository');

  static const String _key = 'history.entries';
  static const int maxEntries = 50;

  /// Returns entries most-recent first. A corrupt store yields an empty list.
  List<HistoryEntry> loadAll() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => HistoryEntry.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false);
    } catch (e) {
      _log.warn('Failed to decode history; resetting. $e');
      return const [];
    }
  }

  /// Prepends [entry] (de-duplicating by analysisId) and persists.
  Future<List<HistoryEntry>> add(HistoryEntry entry) async {
    final current = loadAll().where(
      (e) => e.analysisId != entry.analysisId,
    );
    final updated = [entry, ...current].take(maxEntries).toList(growable: false);
    await _persist(updated);
    return updated;
  }

  /// Removes every stored entry.
  Future<void> clear() async {
    await _prefs.remove(_key);
  }

  HistoryEntry? findById(String analysisId) {
    for (final entry in loadAll()) {
      if (entry.analysisId == analysisId) return entry;
    }
    return null;
  }

  Future<void> _persist(List<HistoryEntry> entries) async {
    final encoded = jsonEncode(
      entries.map((e) => e.toJson()).toList(growable: false),
    );
    await _prefs.setString(_key, encoded);
  }
}
