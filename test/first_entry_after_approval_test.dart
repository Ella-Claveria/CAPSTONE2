// A farmer just approved logs in again before entering the app; that one
// login is still their first time in it, for that account only.
import 'package:agritrade/services/first_entry_after_approval.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('counts once, for the approved account only', () async {
    expect(await FirstEntryAfterApproval.take('farmer-1'), isFalse);

    await FirstEntryAfterApproval.mark('farmer-1');
    expect(await FirstEntryAfterApproval.take('someone-else'), isFalse);
    expect(await FirstEntryAfterApproval.take('farmer-1'), isTrue);
    // Its next login is an ordinary one.
    expect(await FirstEntryAfterApproval.take('farmer-1'), isFalse);
  });
}
