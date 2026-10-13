import 'package:agritrade/screen/admin_filter_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initials come from the first and last name', () {
    expect(adminInitials('Bernadeth Enriquez'), 'BE');
    expect(adminInitials('  juan  dela  cruz '), 'JC');
    expect(adminInitials('Intong'), 'I');
    expect(adminInitials(''), '');
    expect(adminInitials('   '), '');
  });

  Future<void> pump(WidgetTester tester, {required String name}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdminAvatar(name: name)),
        ),
      );

  testWidgets('a farmer with no photo is shown by their initials', (
    tester,
  ) async {
    await pump(tester, name: 'Bernadeth Enriquez');
    expect(find.text('BE'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(
      tester.widget<CircleAvatar>(find.byType(CircleAvatar)).foregroundImage,
      isNull,
    );
  });

  testWidgets('no photo and no name: a plain person icon', (tester) async {
    await pump(tester, name: '');
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
  });

  testWidgets('a photo is the farmer\'s own, with initials behind it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AdminAvatar(
            name: 'Bernadeth Enriquez',
            photoUrl: 'https://example.com/photo.jpg',
          ),
        ),
      ),
    );
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(
      (avatar.foregroundImage! as NetworkImage).url,
      'https://example.com/photo.jpg',
    );
    // What shows if the photo cannot be loaded: never a broken image.
    expect(find.text('BE'), findsOneWidget);
    expect(avatar.onForegroundImageError, isNotNull);
    // The test environment cannot fetch it; that failure is the handled one.
    tester.takeException();
  });
}
