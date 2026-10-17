// "Choose your role": one pill, the chosen side dark green with white
// text, the other dark green text; both halves the same size; no icons.
import 'package:agritrade/theme/app_theme.dart';
import 'package:agritrade/widgets/role_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('switches role, and marks the chosen side', (tester) async {
    var role = 'buyer';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: StatefulBuilder(
                builder: (context, setState) => RoleToggle(
                  selected: role,
                  onChanged: (r) => setState(() => role = r),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Color? colorOf(String label) => tester
        .widget<DefaultTextStyle>(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(DefaultTextStyle),
              )
              .first,
        )
        .style
        .color;

    expect(find.byType(Icon), findsNothing);
    expect(colorOf('Buyer'), Colors.white);
    expect(colorOf('Farmer'), AppTheme.dark);
    // Equal halves.
    expect(
      tester.getSize(find.byType(GestureDetector).first).width,
      tester.getSize(find.byType(GestureDetector).last).width,
    );

    await tester.tap(find.text('Farmer'));
    await tester.pumpAndSettle();
    expect(role, 'farmer');
    expect(colorOf('Farmer'), Colors.white);
    expect(colorOf('Buyer'), AppTheme.dark);
  });
}
