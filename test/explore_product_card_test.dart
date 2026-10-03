import 'package:agritrade/widgets/explore_product_card.dart';
import 'package:agritrade/widgets/save_product_button.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The worst case for the card: a two-line name, a rating, a long price and
// unit, the wholesale badge, a harvest label and a long farmer name.
final _busy = <String, dynamic>{
  'name': 'Native Free-Range Chicken from the Highlands',
  'category': 'Livestock',
  'farmerName': 'Maria Clara de los Santos-Villanueva',
  'retailPrice': 12500,
  'wholesaleEnabled': true,
  'wholesalePrice': 11000,
  'quantity': 1250,
  'unit': 'kg liveweight',
  'rating': 4.8,
  'reviewCount': 128,
  'harvestDate': Timestamp.fromDate(DateTime(2026, 10, 1)),
};

final _plain = <String, dynamic>{
  'name': 'Ube',
  'category': 'Root Crops',
  'farmerName': 'Juan',
  'price': 45,
  'quantity': 3,
  'unit': 'kg',
};

// The Explore grid as BuyerExploreScreen lays it out.
Widget _grid(List<Map<String, dynamic>> products) => MaterialApp(
  home: Scaffold(
    body: LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 12 * 2 - 12) / 2;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          itemCount: products.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: ExploreProductCard.extentFor(
              cardWidth,
              MediaQuery.textScalerOf(context),
            ),
          ),
          itemBuilder: (_, i) => ExploreProductCard(data: products[i]),
        );
      },
    ),
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(_grid([_busy, _plain]));
  await tester.pump();
}

void main() {
  // An overflow is reported as a FlutterError, which fails the test.
  for (final size in const [Size(320, 568), Size(360, 640), Size(412, 915)]) {
    for (final scale in const [1.0, 1.3, 1.6]) {
      testWidgets('no overflow at ${size.width.toInt()}px, text x$scale', (
        tester,
      ) async {
        await _pump(tester, size: size, textScale: scale);
        expect(tester.takeException(), isNull);
        expect(find.byType(ExploreProductCard), findsNWidgets(2));
      });
    }
  }

  testWidgets('cards are the same height whatever their content', (
    tester,
  ) async {
    await _pump(tester, size: const Size(360, 640));
    final cards = find.byType(ExploreProductCard);
    expect(tester.getSize(cards.at(0)), tester.getSize(cards.at(1)));
  });

  testWidgets('the whole card is tappable, image and text alike', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: ExploreProductCard.extentFor(160, TextScaler.noScaling),
              child: ExploreProductCard(data: _busy, onTap: () => taps++),
            ),
          ),
        ),
      ),
    );
    final card = tester.getRect(find.byType(ExploreProductCard));
    await tester.tapAt(card.topCenter + const Offset(0, 20)); // image
    await tester.tapAt(card.center); // name / price area
    await tester.tapAt(card.bottomCenter - const Offset(0, 12)); // farmer row
    expect(taps, 3);
  });

  testWidgets('the heart likes without opening the product', (tester) async {
    var opened = 0;
    var toggled = 0;
    Widget card({required bool saved, VoidCallback? onToggleSave}) =>
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 160,
                height: ExploreProductCard.extentFor(160, TextScaler.noScaling),
                child: ExploreProductCard(
                  data: _busy,
                  saved: saved,
                  onTap: () => opened++,
                  onToggleSave: onToggleSave,
                ),
              ),
            ),
          ),
        );

    // No heart unless the screen asks for one.
    await tester.pumpWidget(card(saved: false));
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);

    await tester.pumpWidget(card(saved: false, onToggleSave: () => toggled++));
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    expect(toggled, 1);
    expect(opened, 0);

    await tester.pumpWidget(card(saved: true, onToggleSave: () => toggled++));
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    // Liked is a filled red heart, not just a different outline.
    expect(
      tester.widget<Icon>(find.byIcon(Icons.favorite_rounded)).color,
      LikeHeart.likedColor,
    );
    // Let the tap's bounce animation finish.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long name is cut at two lines', (tester) async {
    await _pump(tester, size: const Size(320, 568));
    final name = tester.widget<Text>(
      find.text('Native Free-Range Chicken from the Highlands'),
    );
    expect(name.maxLines, 2);
    expect(name.overflow, TextOverflow.ellipsis);
  });

  testWidgets('wholesale badge only shows when wholesale is on', (
    tester,
  ) async {
    await _pump(tester, size: const Size(360, 640));
    // Its slot is kept on every card (for equal heights) but only painted
    // where wholesale applies.
    final badges = tester
        .widgetList<Visibility>(
          find.ancestor(
            of: find.text('Wholesale available'),
            matching: find.byType(Visibility),
          ),
        )
        .map((v) => v.visible)
        .toList();
    expect(badges, [true, false]);
  });
}
