import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glow_field.dart';

/// A form field in the registration form's design, for use inside a
/// [Form]: the label above the field (never inside it), the rounded white
/// [GlowField] with its icon, and the error or a short caption on its own
/// line underneath.
///
/// Validation works as with a TextFormField: [validator] gets the field's
/// text when the form is validated.
class AgriFormField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final FormFieldValidator<String>? validator;
  final String? caption;
  final bool obscureText;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  /// Shows the value without letting it be edited.
  final bool readOnly;

  /// [AutovalidateMode.always] re-checks the field each time it is rebuilt,
  /// so an error can show while typing.
  final AutovalidateMode? autovalidateMode;

  const AgriFormField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
    this.validator,
    this.caption,
    this.obscureText = false,
    this.suffix,
    this.keyboardType,
    this.onSubmitted,
    this.autofocus = false,
    this.readOnly = false,
    this.autovalidateMode,
  });

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      autovalidateMode: autovalidateMode,
      validator: (_) => validator?.call(controller.text),
      builder: (state) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTheme.label()),
            const SizedBox(height: 8),
            GlowField(
              controller: controller,
              hint: hint,
              icon: icon,
              obscureText: obscureText,
              suffix: suffix,
              keyboardType: keyboardType,
              onSubmitted: onSubmitted,
              autofocus: autofocus,
              readOnly: readOnly,
            ),
            if (state.hasError) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 14,
                    color: Colors.red.shade700,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      state.errorText!,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (caption != null) ...[
              const SizedBox(height: 6),
              Text(
                caption!,
                style: TextStyle(color: Colors.grey[600], fontSize: 11.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
