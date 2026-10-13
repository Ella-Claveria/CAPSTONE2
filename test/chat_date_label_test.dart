import 'package:agritrade/services/chat_date_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 9, 15, 30); // a Friday

  test('today and yesterday are named', () {
    expect(chatDayLabel(DateTime(2026, 10, 9, 0, 5), now: now), 'Today');
    expect(chatDayLabel(DateTime(2026, 10, 8, 23, 59), now: now), 'Yesterday');
  });

  test('older days show the day and date', () {
    expect(
      chatDayLabel(DateTime(2026, 10, 5, 9), now: now),
      'Monday, October 5',
    );
    expect(
      chatDayLabel(DateTime(2025, 12, 31, 9), now: now),
      'Wednesday, December 31, 2025',
    );
  });

  test('a message still being sent counts as today', () {
    expect(chatDayLabel(null, now: now), 'Today');
  });

  test('a heading goes above the first message of each day only', () {
    final morning = DateTime(2026, 10, 8, 8);
    final evening = DateTime(2026, 10, 8, 21);
    final nextDay = DateTime(2026, 10, 9, 0, 1);
    // The very first message of the conversation.
    expect(startsNewChatDay(morning, null), isTrue);
    // Same day: no second heading.
    expect(startsNewChatDay(evening, morning), isFalse);
    // Two minutes apart, but across midnight.
    expect(startsNewChatDay(nextDay, DateTime(2026, 10, 8, 23, 59)), isTrue);
    // Same day number in a different month.
    expect(startsNewChatDay(DateTime(2026, 11, 8), morning), isTrue);
  });

  test('a message still being sent is compared as if sent now', () {
    expect(startsNewChatDay(null, DateTime(2026, 10, 9, 9), now: now), isFalse);
    expect(startsNewChatDay(null, DateTime(2026, 10, 8, 9), now: now), isTrue);
  });
}
