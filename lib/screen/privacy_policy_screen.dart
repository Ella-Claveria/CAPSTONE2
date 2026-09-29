import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

class _LegalSection {
  final String heading;
  final List<String> lines;
  const _LegalSection(this.heading, this.lines);
}

/// AgriTrade+ Privacy Policy — what data is collected, why, and how
/// location/notifications are handled. Kept separate from
/// TermsAndConditionsScreen (platform conduct rules) per the client's
/// requirement that the two stay distinct documents. The location-privacy
/// wording here (sections E1/E2) is the same wording used in the farmer/buyer
/// location permission dialogs (see location_permission_prompt.dart) and the
/// farmer Public Location Preview (see register_screen.dart) — kept in sync
/// on purpose so the policy always matches what the app actually does.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const List<_LegalSection> _sections = [
    _LegalSection('A. Information Collected', [
      'AgriTrade+ may collect: your name, email address, contact number, user '
          'role, account/profile details, farmer verification information, '
          'product listings, order and transaction records, messages, search '
          'activity, notification-related information, and location '
          'information when needed.',
    ]),
    _LegalSection('B. Why Information Is Collected', [
      'This information is used for: account creation, login/authentication, '
          'farmer verification, product listings, orders and transactions, '
          'messaging, notifications, location-based marketplace features, '
          'system analytics, security, moderation, and improving the app.',
    ]),
    _LegalSection('C. Email Verification', [
      "Your email address may be used to verify your account and to support "
          "authentication and account recovery. Email verification is not "
          "connected to push notification permission — enabling or disabling "
          "notifications never affects your account's email verification.",
    ]),
    _LegalSection('D. Notification Data', [
      'If you enable notifications, AgriTrade+ may send updates about: new '
          'orders, order status changes, messages, transaction updates, farmer '
          'verification results, warnings, suspension/ban notices, and other '
          'important account activity.',
      'You can change notification permission later in your device settings.',
    ]),
    _LegalSection('E. Location Information', [
      'Location handling is explained separately for Farmers and Buyers below.',
    ]),
    _LegalSection('E1. Farmer Location', [
      'Location is required for location-based marketplace features and for '
          'identifying the general location of your products/farm.',
      'Your public location shown to buyers is your Barangay, Municipality/'
          'City, and Province (for example: "Brgy. Bugaan East, Laurel, Batangas").',
      'AgriTrade+ does not publicly display your exact latitude, longitude, or '
          'home address, unless a separate transaction-specific feature '
          'explicitly requires and allows a more precise location.',
      'Your precise location will not be publicly displayed to other users.',
      'Precise coordinates may be stored internally for distance calculation, '
          'nearby product discovery, maps, other location-based features, and '
          'aggregated analytics.',
    ]),
    _LegalSection('E2. Buyer Location', [
      'Your location may be used for nearby products, nearby farmers, '
          'approximate distance, map/location-based features, and aggregated '
          'demand analytics.',
      'Your precise location is not publicly displayed to other users.',
    ]),
    _LegalSection('F. Data Privacy Act', [
      'AgriTrade+ is designed to handle personal information in accordance '
          'with applicable data privacy requirements, including the principles '
          'of the Philippine Data Privacy Act of 2012 (Republic Act No. 10173), '
          'where applicable.',
      'This Privacy Policy does not constitute a legal guarantee of compliance.',
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
        title: Text('Privacy Policy', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 17)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Text(
            'AgriTrade+ Privacy Policy',
            style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 6),
          Text(
            'This Privacy Policy explains what information AgriTrade+ collects, why, '
            'and how it is used and protected.',
            style: GoogleFonts.montserrat(fontSize: 12.5, color: Colors.black54, height: 1.5),
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
