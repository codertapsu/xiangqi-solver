import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:xiangqi_solver/core/utils/relative_time.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('vi');
  });

  final now = DateTime(2026, 10, 18, 15, 30);

  test('English', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(relativeTime(l10n, now, now: now), 'Just now');
    expect(relativeTime(l10n, now.add(const Duration(minutes: 5)), now: now), 'Just now');
    expect(relativeTime(l10n, now.subtract(const Duration(minutes: 1)), now: now), '1 minute ago');
    expect(relativeTime(l10n, now.subtract(const Duration(minutes: 42)), now: now), '42 minutes ago');
    expect(relativeTime(l10n, now.subtract(const Duration(hours: 3)), now: now), '3 hours ago');
    expect(relativeTime(l10n, DateTime(2026, 10, 17, 9, 5), now: now), 'Yesterday 09:05');
    expect(relativeTime(l10n, DateTime(2026, 9, 2, 9, 5), now: now), 'Sep 2, 2026 09:05');
  });

  test('Vietnamese', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('vi'));
    expect(relativeTime(l10n, now, now: now), 'Vừa xong');
    expect(relativeTime(l10n, now.subtract(const Duration(minutes: 42)), now: now), '42 phút trước');
    expect(relativeTime(l10n, now.subtract(const Duration(hours: 3)), now: now), '3 giờ trước');
    expect(relativeTime(l10n, DateTime(2026, 10, 17, 9, 5), now: now), 'Hôm qua 9:05'); // vi uses H:mm
  });
}
