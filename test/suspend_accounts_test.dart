// Suspend Accounts: how many reports stand against each account, which
// decides which accounts are flagged (10 or more) and listed first.
import 'package:agritrade/screen/admin_suspend_accounts_dialog.dart';
import 'package:agritrade/screen/admin_user_accounts_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports are counted by the reported account; dismissed ones are not '
      'counted', () {
    final counts = reportCountsByAccount([
      for (var i = 0; i < 11; i++) {'reportedUserId': 'buyer-1'},
      {'reportedUserId': 'farmer-1'},
      // An older listing report names only the farmer.
      {'farmerId': 'farmer-1'},
      {'reportedUserId': 'farmer-1', 'moderationAction': 'dismissed'},
      // About no account at all.
      {'reason': 'spam'},
    ]);
    expect(counts, {'buyer-1': 11, 'farmer-1': 2});
    expect(counts['buyer-1']! >= kSuspendReportThreshold, isTrue);
    expect(counts['farmer-1']! >= kSuspendReportThreshold, isFalse);
  });

  test('a suspension says until when', () {
    expect(suspensionUntilLabel(null), 'Until an Admin reactivates it');
    expect(
      suspensionUntilLabel(DateTime(2026, 10, 17, 10, 51)),
      'Until Oct 17, 2026 · 10:51 AM',
    );
    // 24 hours is the first choice, so the default.
    expect(kSuspensionLengths.first.duration, const Duration(hours: 24));
  });
}
