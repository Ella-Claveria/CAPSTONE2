// The login hero's typed-out headline: one character at a time, then the
// subtitle; complete at once when animations are turned off; and nothing
// left running when the screen goes away.
import 'package:agritrade/widgets/typewriter_headline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _text = 'Connecting Farmers to Better Markets';

Widget _app({bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: const Scaffold(
      body: TypewriterHeadline(
        text: _text,
        highlight: 'Better Markets',
        subtitle: 'Grow together. Trade smarter.',
      ),
    ),
  ),
);

TypewriterHeadlineState _state(WidgetTester tester) =>
    tester.state(find.byType(TypewriterHeadline));

// The words the reader can see: the spans that are not transparent.
String _visible(WidgetTester tester) {
  final rich = tester.widget<RichText>(
    find
        .descendant(
          of: find.byType(TypewriterHeadline),
          matching: find.byType(RichText),
        )
        .first,
  );
  final buffer = StringBuffer();
  rich.text.visitChildren((span) {
    if (span is TextSpan &&
        span.text != null &&
        span.style?.color != Colors.transparent) {
      buffer.write(span.text);
    }
    return true;
  });
  return buffer.toString();
}

void main() {
  testWidgets('types the headline one character at a time, then the subtitle', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    expect(_state(tester).typedLength, 0);

    // 450 ms start delay, then 60 ms a character.
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 600));
    final early = _state(tester).typedLength;
    expect(early, inInclusiveRange(9, 11));
    expect(_visible(tester), _text.substring(0, early));
    expect(_state(tester).subtitleShown, isFalse);

    await tester.pump(const Duration(milliseconds: 60));
    expect(_state(tester).typedLength, early + 1);

    // Finished: the whole headline, and after the pause the subtitle.
    await tester.pump(const Duration(milliseconds: 60 * _text.length));
    expect(_state(tester).typedLength, _text.length);
    expect(_visible(tester), _text);
    expect(_state(tester).subtitleShown, isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_state(tester).subtitleShown, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Grow together. Trade smarter.'), findsOneWidget);
    // The headline stays.
    expect(_visible(tester), _text);
  });

  testWidgets('"Better Markets" is in the light green', (tester) async {
    await tester.pumpWidget(_app(reduceMotion: true));
    final rich = tester.widget<RichText>(
      find
          .descendant(
            of: find.byType(TypewriterHeadline),
            matching: find.byType(RichText),
          )
          .first,
    );
    final colors = <String, Color?>{};
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text != null) {
        colors[span.text!] = span.style?.color;
      }
      return true;
    });
    expect(colors['Better Markets'], const Color(0xFFB9E58C));
    expect(colors['Connecting Farmers to '], Colors.white);
  });

  testWidgets('with animations turned off it is complete at once', (
    tester,
  ) async {
    await tester.pumpWidget(_app(reduceMotion: true));
    expect(_state(tester).typedLength, _text.length);
    expect(_state(tester).subtitleShown, isTrue);
  });

  testWidgets('leaving mid-animation leaves no timer running', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    // The test framework fails here if a timer or ticker is still active.
    await tester.pump(const Duration(seconds: 5));
  });
}
