import 'package:agritrade/screen/admin_dashboard_screen.dart';
import 'package:agritrade/screen/admin_filter_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the actions beside the tabs can be clicked, and so can the '
      'tabs', (tester) async {
    var cleared = 0;
    String? opened;
    await tester.binding.setSurfaceSize(const Size(1400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminThemeScope(
            palette: AdminPalette.light,
            child: AdminTabbedTable<String>(
              selected: 'all',
              onSelected: (tab) => opened = tab,
              tabs: const [
                (
                  value: 'all',
                  label: 'All accounts',
                  count: 6,
                  icon: Icons.groups_2_outlined,
                ),
                (
                  value: 'buyers',
                  label: 'Buyers',
                  count: 3,
                  icon: Icons.shopping_basket_outlined,
                ),
              ],
              trailing: TextButton(
                onPressed: () => cleared++,
                child: const Text('Clear Selection'),
              ),
              child: const SizedBox(height: 200, width: double.infinity),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Clear Selection'));
    expect(cleared, 1);

    await tester.tap(find.text('Buyers'));
    expect(opened, 'buyers');
  });
}
