import 'package:intl/intl.dart';

/// The day headings shown in the middle of a conversation, where each
/// day's messages begin — so scrolling back shows on which day something
/// was said, not only at what time.

/// Whether a message sent at [current] is the first of its day, given the
/// message just before it was sent at [previous] (null when there is no
/// earlier message). A message still being sent has no time yet and is
/// treated as sent now.
bool startsNewChatDay(DateTime? current, DateTime? previous, {DateTime? now}) {
  if (previous == null) return true;
  final a = current ?? now ?? DateTime.now();
  return a.year != previous.year ||
      a.month != previous.month ||
      a.day != previous.day;
}

/// "Today", "Yesterday", or the day and date — "Monday, October 5", with
/// the year added once it is not the current one.
String chatDayLabel(DateTime? date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final day = date ?? today;
  final daysAgo = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime(day.year, day.month, day.day)).inDays;
  if (daysAgo == 0) return 'Today';
  if (daysAgo == 1) return 'Yesterday';
  return DateFormat(
    day.year == today.year ? 'EEEE, MMMM d' : 'EEEE, MMMM d, y',
  ).format(day);
}
