import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A pill-shaped field styled after the reference design: icon, a thin
/// vertical divider, then the text — sitting on a plain white plate with a
/// faint lift shadow at rest. The brand-green glow around the whole plate
/// switches on only while the field actually has focus (i.e. the user is
/// typing into it), not all the time. Shared by the login and registration
/// forms so both use the exact same field design.
class GlowField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;
  // e.g. [AutofillHints.email] / [AutofillHints.password] — lets the OS's
  // own password manager (Google/iCloud) recognize and offer to save or
  // fill this field, instead of the app remembering anything itself.
  final Iterable<String>? autofillHints;

  const GlowField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.textInputAction,
    this.onSubmitted,
    this.errorText,
    this.autofillHints,
  });

  @override
  State<GlowField> createState() => _GlowFieldState();
}

class _GlowFieldState extends State<GlowField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focused != _focusNode.hasFocus) {
        setState(() => _focused = _focusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: AppTheme.glowFieldWrapper(focused: _focused),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 18, right: 12),
            child: Icon(widget.icon, color: AppTheme.mid, size: 20),
          ),
          Container(height: 22, width: 1, color: Colors.black12),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              keyboardType: widget.keyboardType,
              obscureText: widget.obscureText,
              textInputAction: widget.textInputAction,
              onSubmitted: widget.onSubmitted,
              autofillHints: widget.autofillHints,
              decoration: InputDecoration(
                hintText: widget.hint,
                suffixIcon: widget.suffix,
                errorText: widget.errorText,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
