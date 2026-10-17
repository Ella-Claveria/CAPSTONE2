import 'package:flutter/material.dart';

/// The AgriTrade+ password rules — the same for registration and for
/// Change Password, so a password allowed in one is allowed in the other.
class PasswordRules {
  PasswordRules._();

  static const int minLength = 12;

  static bool hasUppercase(String p) => RegExp(r'[A-Z]').hasMatch(p);
  static bool hasLowercase(String p) => RegExp(r'[a-z]').hasMatch(p);
  static bool hasNumber(String p) => RegExp(r'[0-9]').hasMatch(p);
  static bool hasSymbol(String p) =>
      RegExp(r'''[!@#$%^&*(),.?":{}|<>_+\-=\[\]]''').hasMatch(p);

  /// Each rule's label and whether [p] meets it, in the order shown.
  static List<(String, bool)> check(String p) => [
    ('$minLength+ characters', p.length >= minLength),
    ('Uppercase letter', hasUppercase(p)),
    ('Lowercase letter', hasLowercase(p)),
    ('Number', hasNumber(p)),
    ('Symbol', hasSymbol(p)),
  ];

  static bool meetsAll(String p) => check(p).every((rule) => rule.$2);
}

/// The live checklist under a new-password field: hidden until something
/// is typed, then each rule turns green the moment it is met — and once
/// every rule is met the list folds away, since there is nothing left to
/// do (it comes back if the password is changed so one is no longer met).
class PasswordRequirementsChecklist extends StatelessWidget {
  final String password;

  /// Space under the list (and its height while hidden).
  final double bottomSpacing;

  const PasswordRequirementsChecklist({
    super.key,
    required this.password,
    this.bottomSpacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    final hidden = password.isEmpty || PasswordRules.meetsAll(password);
    // Folds smoothly instead of making the form below jump.
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: hidden ? SizedBox(height: bottomSpacing) : _list(),
    );
  }

  Widget _list() {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          for (final (label, met) in PasswordRules.check(password))
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  met ? Icons.check_circle : Icons.circle_outlined,
                  size: 14,
                  color: met ? Colors.green[600] : Colors.grey[400],
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: met ? FontWeight.w600 : FontWeight.normal,
                    color: met ? Colors.green[700] : Colors.grey[600],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
