import 'package:agritrade/widgets/login_form_fields.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saved admin email and password are removed, nothing else', () async {
    SharedPreferences.setMockInitialValues({
      'admin_saved_password': 'legacy-test-password',
      'admin_saved_email': 'admin@example.com',
      'walkthrough_seen_buyer': true,
    });

    await LoginFormFields.clearSavedAdminPassword();
    await LoginFormFields.clearSavedAdminPassword();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('admin_saved_password'), isFalse);
    expect(prefs.containsKey('admin_saved_email'), isFalse);
    expect(prefs.getBool('walkthrough_seen_buyer'), isTrue);
  });
}
