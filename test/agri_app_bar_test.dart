// Inner-screen header: dark green, and out of the way while reading —
// scrolling down hides it, scrolling back up shows it again.
import 'package:agritrade/widgets/agri_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> pump(WidgetTester tester, {Widget? titleWidget}) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: titleWidget == null
              ? const AgriAppBar(title: 'Inventory')
              : AgriAppBar(titleWidget: titleWidget),
          body: ListView(
            children: [
              for (var i = 0; i < 40; i++)
                SizedBox(height: 60, child: Text('Row $i')),
            ],
          ),
        ),
      ),
    );
  }

  double barHeight(WidgetTester tester) =>
      tester.getSize(find.byType(AgriAppBar)).height;

  testWidgets('scrolling down hides it, scrolling up brings it back', (
    tester,
  ) async {
    await pump(tester);
    expect(barHeight(tester), AgriAppBar.height);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(barHeight(tester), 0);

    await tester.drag(find.byType(ListView), const Offset(0, 80));
    await tester.pumpAndSettle();
    expect(barHeight(tester), AgriAppBar.height);
  });

  testWidgets('a search or chat header stays put', (tester) async {
    await pump(tester, titleWidget: const Text('Juan'));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(barHeight(tester), AgriAppBar.height);
  });
}
