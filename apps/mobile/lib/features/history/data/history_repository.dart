import 'dart:convert';
import 'dart:io';

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
    final combined = [entry, ...current].toList(growable: false);
    final updated = combined.take(maxEntries).toList(growable: false);
    // Delete screenshots for entries dropped by the cap so old images don't
    // linger on disk after they fall out of the visible history.
    for (final dropped in combined.skip(maxEntries)) {
      await _deleteScreenshot(dropped.screenshotPath);
    }
    await _persist(updated);
    return updated;
  }

  /// Removes every stored entry AND deletes any saved screenshot files they
  /// referenced, so clearing history also reclaims the on-device image storage.
  Future<void> clear() async {
    for (final entry in loadAll()) {
      await _deleteScreenshot(entry.screenshotPath);
    }
    await _prefs.remove(_key);
  }

  /// Best-effort delete of a saved screenshot file; never throws.
  Future<void> _deleteScreenshot(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      _log.warn('Failed to delete screenshot $path: $e');
    }
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
