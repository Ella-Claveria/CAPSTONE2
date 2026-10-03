import 'package:agritrade/services/conversation_prefs_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'nickname applies only to its own conversation, and can be removed',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = ConversationPrefs.instance;
      await prefs.load('buyer-1');

      prefs.setNickname('convA', '  Rhon  ');
      expect(prefs.displayName('convA', 'Rhonald Reyes'), 'Rhon');
      // Another conversation with a different (or even the same) person keeps
      // the real name.
      expect(prefs.displayName('convB', 'Rhonald Reyes'), 'Rhonald Reyes');

      // Blank removes it — the real name comes back.
      prefs.setNickname('convA', '   ');
      expect(prefs.nicknameFor('convA'), isNull);
      expect(prefs.displayName('convA', 'Rhonald Reyes'), 'Rhonald Reyes');

      // Persisted per account, and not visible to a different account.
      prefs.setNickname('convA', 'Kuya R | farm');
      await Future<void>.delayed(Duration.zero);
      await prefs.load('buyer-2');
      expect(prefs.nicknameFor('convA'), isNull);
      await prefs.load('buyer-1');
      expect(prefs.nicknameFor('convA'), 'Kuya R | farm');
    },
  );

  test('nickname is capped at the maximum length', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = ConversationPrefs.instance;
    await prefs.load('buyer-3');
    prefs.setNickname('convC', 'x' * 100);
    expect(
      prefs.nicknameFor('convC')!.length,
      ConversationPrefs.nicknameMaxLength,
    );
  });
}
