import 'package:agritrade/screen/chat_attachments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the + menu floats above the button and keeps the composer', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    ChatAttachment? picked;
    var closed = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              ChatComposerBar(
                controller: controller,
                hintText: 'Message Rhona...',
                sending: false,
                onSend: () {},
                onAttach: (plusContext) async {
                  picked = await showChatAttachmentMenu(plusContext);
                  closed++;
                },
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    final plus = find.byTooltip('Attach');
    await tester.tap(plus);
    await tester.pumpAndSettle();

    // Small menu, opening upward from the + button; composer still shown
    // and still focused (the keyboard isn't dismissed).
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Choose Photo'), findsOneWidget);
    expect(find.text('Share Location'), findsOneWidget);
    expect(find.text('Attach'), findsNothing); // no sheet title
    final plusRect = tester.getRect(plus);
    expect(
      tester.getRect(find.text('Share Location')).bottom,
      lessThan(plusRect.top),
    );
    expect(find.byType(ChatComposerBar), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );

    // Tapping outside closes it with no choice.
    await tester.tapAt(const Offset(400, 40));
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsNothing);
    expect(picked, isNull);
    expect(closed, 1);

    // Picking an item returns it.
    await tester.tap(plus);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose Photo'));
    await tester.pumpAndSettle();
    expect(picked, ChatAttachment.gallery);
    expect(tester.takeException(), isNull);
  });
}
