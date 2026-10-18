import 'package:intl/intl.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

/// "just now" / "5 minutes ago" / "3 hours ago" / "yesterday 21:40" / a date.
String relativeTime(AppLocalizations l10n, DateTime when, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final diff = current.difference(when);
  if (diff.isNegative || diff.inMinutes < 1) return l10n.timeJustNow;
  if (diff.inMinutes < 60) return l10n.timeMinutesAgo(diff.inMinutes);
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(when.year, when.month, when.day);
  final time = DateFormat.Hm(l10n.localeName).format(when);
  if (day == today) return l10n.timeHoursAgo(diff.inHours);
  if (today.difference(day).inDays == 1) return l10n.timeYesterdayAt(time);
  return DateFormat.yMMMd(l10n.localeName).add_Hm().format(when);
}
