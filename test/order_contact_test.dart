// Phone contact on an order: when the two sides may see each other's
// number, and what Order Details shows in each case.
import 'package:agritrade/services/order_contact_service.dart';
import 'package:agritrade/widgets/order_contact_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Widget host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  test('numbers are shared only while confirmed or shipped', () {
    expect(OrderContactService.isShared('pending'), isFalse);
    expect(OrderContactService.isShared('confirmed'), isTrue);
    expect(OrderContactService.isShared('shipped'), isTrue);
    expect(OrderContactService.isShared('completed'), isFalse);
    expect(OrderContactService.isShared('rejected'), isFalse);
    expect(OrderContactService.isShared('cancelled'), isFalse);
  });

  test('every accepted way of writing a number is stored the same', () {
    for (final raw in ['09123456789', '+639123456789', '9123456789']) {
      expect(OrderContactService.normalized(raw), '+639123456789');
    }
    expect(OrderContactService.normalized('12345'), '');
    expect(OrderContactService.normalized('08123456789'), '');
    expect(OrderContactService.normalized(null), '');
  });

  testWidgets('a pending order shows no number, and never looks one up', (
    tester,
  ) async {
    var lookups = 0;
    await tester.pumpWidget(
      host(
        OrderContactSection(
          orderId: 'o1',
          status: 'pending',
          viewerIsFarmer: true,
          legacyBuyerContact: '+639123456789',
          loadContact: () async {
            lookups++;
            return '+639123456789';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('shared once the farmer confirms'), findsOne);
    expect(find.textContaining('+639'), findsNothing);
    expect(lookups, 0);
  });

  testWidgets('a confirmed order shows the other side\'s number', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        OrderContactSection(
          orderId: 'o1',
          status: 'confirmed',
          viewerIsFarmer: true,
          loadContact: () async => '+639123456789',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('+639123456789'), findsOneWidget);
    expect(find.byTooltip('Call'), findsOneWidget);
    expect(find.byTooltip('Copy number'), findsOneWidget);
    expect(find.textContaining('Messages is still the best way'), findsOne);
  });

  testWidgets('confirming while the screen is open brings the number in', (
    tester,
  ) async {
    Widget section(String status) => host(
      OrderContactSection(
        orderId: 'o1',
        status: status,
        viewerIsFarmer: false,
        loadContact: () async => '+639987654321',
      ),
    );
    await tester.pumpWidget(section('pending'));
    await tester.pumpAndSettle();
    expect(find.text('+639987654321'), findsNothing);
    await tester.pumpWidget(section('confirmed'));
    await tester.pumpAndSettle();
    expect(find.text('+639987654321'), findsOneWidget);
  });

  testWidgets('no number on the order points to Messages instead', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        OrderContactSection(
          orderId: 'o1',
          status: 'shipped',
          viewerIsFarmer: false,
          loadContact: () async => '',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('has no contact number'), findsOne);
    expect(find.byTooltip('Call'), findsNothing);
  });

  testWidgets('reporting a wrong number files it once, without the number', (
    tester,
  ) async {
    final sent = <String>[];
    await tester.pumpWidget(
      host(
        OrderContactSection(
          orderId: 'o42',
          status: 'confirmed',
          viewerIsFarmer: true,
          loadContact: () async => '+639123456789',
          sendReport: (subject, message) async {
            sent.add('$subject|$message');
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Report incorrect number'));
    await tester.pumpAndSettle();
    // Backing out sends nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);

    await tester.tap(find.text('Report incorrect number'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    expect(sent, hasLength(1));
    expect(sent.single, contains('o42'));
    expect(sent.single.contains('+639123456789'), isFalse);
    expect(find.text('Reported to support'), findsOneWidget);
    // Cannot be sent a second time.
    await tester.tap(find.text('Reported to support'));
    await tester.pumpAndSettle();
    expect(sent, hasLength(1));
  });
}
