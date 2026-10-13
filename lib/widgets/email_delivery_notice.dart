import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// The "can't find the email?" note shown after the app has asked for an
/// account email (password reset link, verification code): a rounded pale
/// green box with an info icon. Account emails sometimes land in Spam, so
/// both screens say the same thing in the same way.
class EmailDeliveryNotice extends StatelessWidget {
  final String text;

  const EmailDeliveryNotice({
    super.key,
    this.text =
        "Can't find the email? Please check your Spam or Junk folder. "
        'The email may take a few minutes to arrive.',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.mid.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppTheme.mid),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.montserrat(
                fontSize: 12.5,
                height: 1.45,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
