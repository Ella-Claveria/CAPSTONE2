import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// The 6-digit verification code input: six boxes drawn from one real text
/// field laid over them — so typing, backspace, paste and the keyboard's
/// own "code from email" suggestion all behave like a normal field.
///
/// The owner rebuilds it when [controller] or [focusNode] changes (both
/// are listened to by the screen or dialog that holds them).
class OtpCodeField extends StatelessWidget {
  static const int length = 6;

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  const OtpCodeField({
    super.key,
    required this.controller,
    required this.focusNode,
    this.enabled = true,
    this.autofocus = true,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final code = controller.text;
    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < length; i++) ...[
              if (i > 0) SizedBox(width: i == length ~/ 2 ? 14 : 6),
              Flexible(
                child: _CodeBox(
                  digit: i < code.length ? code[i] : '',
                  active:
                      focusNode.hasFocus &&
                      (i == code.length ||
                          (i == length - 1 && code.length == length)),
                ),
              ),
            ],
          ],
        ),
        Positioned.fill(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            autofocus: autofocus,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(length),
            ],
            showCursor: false,
            enableInteractiveSelection: false,
            style: const TextStyle(color: Colors.transparent, fontSize: 1),
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              filled: false,
              counterText: '',
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: onSubmitted,
          ),
        ),
      ],
    );
  }
}

// One digit of the code.
class _CodeBox extends StatelessWidget {
  final String digit;
  final bool active;

  const _CodeBox({required this.digit, required this.active});

  @override
  Widget build(BuildContext context) {
    final filled = digit.isNotEmpty;
    return Container(
      constraints: const BoxConstraints(maxWidth: 46),
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? AppTheme.accent.withValues(alpha: 0.35) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active || filled ? AppTheme.dark : Colors.grey.shade300,
          width: active ? 2 : 1.2,
        ),
      ),
      child: Text(
        digit,
        style: AppTheme.heading(22).copyWith(color: AppTheme.dark),
      ),
    );
  }
}
