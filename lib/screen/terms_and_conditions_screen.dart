import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

class _LegalSection {
  final String heading;
  final List<String> lines;
  const _LegalSection(this.heading, this.lines);
}

/// AgriTrade+ Terms & Conditions — plain-language rules for using the
/// platform. Opened from the registration consent checkbox and from
/// Settings/Help. Kept separate from PrivacyPolicyScreen, which covers what
/// data is collected and how it's used instead of platform conduct rules.
class TermsAndConditionsScreen extends StatelessWidget {
  const TermsAndConditionsScreen({super.key});

  static const List<_LegalSection> _sections = [
    _LegalSection('A. Acceptance of Terms', [
      'By creating and using an AgriTrade+ account, you agree to follow these '
          'Terms & Conditions and the rules of the platform.',
    ]),
    _LegalSection('B. User Accounts', [
      'You are responsible for providing accurate information when creating your account.',
      'You are responsible for keeping your login credentials secure.',
      'You must not allow unauthorized use of your account.',
    ]),
    _LegalSection('C. User Roles', [
      'AgriTrade+ has two public account roles: Farmer and Buyer.',
      'Admin is an internal management role used to review and moderate the '
          'platform. It is not a public registration role — AgriTrade+ does not '
          'allow public admin sign-up.',
    ]),
    _LegalSection('D. Farmer Responsibilities', [
      'Provide accurate product information.',
      'Provide accurate quantities and pricing.',
      'Keep product availability updated.',
      'Avoid misleading or fraudulent listings.',
      'Follow the Supported Products scope (see section E).',
    ]),
    _LegalSection('E. Supported Products', [
      'AgriTrade+ currently accepts only selected commodities covered by the '
          'approved system scope.',
      'Farmers may only publish listings for products available in the '
          'Supported Products list.',
      'Unsupported products cannot be listed until they are officially added '
          'to the system.',
      'The supported-product list may be updated in the future based on the '
          'agricultural office/client and system scope.',
    ]),
    _LegalSection('F. Buyer Responsibilities', [
      'Provide accurate account information.',
      'Use the platform responsibly.',
      'Avoid fraudulent orders.',
      'Communicate appropriately with farmers.',
      'Follow transaction rules.',
    ]),
    _LegalSection('G. Product Listings', [
      'Product information must be accurate.',
      'Product quantity and availability should be kept updated.',
      'Prohibited or unsupported listings may be removed.',
    ]),
    _LegalSection('H. Orders and Transactions', [
      'Buyers may place orders through the app.',
      'Farmers may accept or reject orders according to the system flow.',
      'Users should complete transactions honestly.',
      'AgriTrade+ records transaction activity for system functionality and analytics.',
    ]),
    _LegalSection('I. Messaging and Communication', [
      'Messaging must not be used for harassment, scams, abusive content, '
          'fraudulent activity, or prohibited transactions.',
    ]),
    _LegalSection('J. Reports and Moderation', [
      'Users may report listings or other users.',
      'Admin may review reports, issue warnings, hide or remove listings, and '
          'suspend or ban accounts when necessary.',
    ]),
    _LegalSection('K. Account Suspension / Ban', [
      'Accounts may be restricted, suspended, or banned for violations such as:',
      'Fraud.',
      'Repeated abusive behavior.',
      'Misleading product information.',
      'Prohibited activity.',
      'Serious Terms violations.',
    ]),
    _LegalSection('L. Platform Availability', [
      'AgriTrade+ requires internet access for most functions.',
      'The app may occasionally be unavailable due to maintenance, network '
          'problems, or technical issues.',
    ]),
    _LegalSection('M. Changes to Terms', [
      'These Terms may be updated when necessary, and users may be informed '
          'of major changes.',
    ]),
    _LegalSection('N. Contact / Support', [
      'For questions about these Terms, use AgriTrade+\'s existing contact or '
          'help/support option.',
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        backgroundColor: AppTheme.dark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Terms & Conditions', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 17)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Text(
            'AgriTrade+ Terms & Conditions',
            style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 6),
          Text(
            'Please read these Terms carefully before using AgriTrade+.',
            style: GoogleFonts.montserrat(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 20),
          for (final section in _sections) ...[
            Text(
              section.heading,
              style: GoogleFonts.montserrat(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppTheme.dark),
            ),
            const SizedBox(height: 6),
            for (final line in section.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 2),
                child: Text(
                  line,
                  style: GoogleFonts.montserrat(fontSize: 12.5, color: Colors.black87, height: 1.5),
                ),
              ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}
