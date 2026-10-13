import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import 'agri_dialog.dart';

/// What each part of the Farmer's Market tab shows, and whose data it is.
/// The first is the farmer's own; the rest cover the whole marketplace,
/// which is why they can already have figures on a brand-new account.
const List<({String title, String scope, String body})> kMarketGuideItems = [
  (
    title: 'Sales Performance',
    scope: 'Your sales',
    body:
        'Your own revenue from completed orders. It stays empty until '
        'your first order is completed.',
  ),
  (
    title: 'Current Market Average',
    scope: 'Whole marketplace',
    body:
        'The average price other farmers are asking right now for each '
        'product. Use it as a guide when setting your price.',
  ),
  (
    title: 'Best-Selling Products',
    scope: 'Whole marketplace',
    body: 'The products buyers purchased most across AgriTrade+ this month.',
  ),
  (
    title: 'Top Buyer Locations',
    scope: 'Whole marketplace',
    body: 'The areas where the most completed orders came from this month.',
  ),
];

String _seenKey(String uid) => 'market_tab_guide_seen_$uid';

/// Shows the Market tab guide the first time this account opens the tab on
/// this device, and never again after it is closed.
Future<void> showMarketTabGuideOnce(BuildContext context) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    return;
  }
  if (prefs.getBool(_seenKey(uid)) == true) return;
  if (!context.mounted) return;
  await showMarketTabGuide(context);
  await prefs.setBool(_seenKey(uid), true);
}

/// The guide itself.
Future<void> showMarketTabGuide(BuildContext context) {
  return showAgriDialog<void>(
    context: context,
    builder: (dialogContext) => AgriDialog(
      scrollable: true,
      title: const Text('Your Market tab'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Some cards show your own sales. Others show the whole '
            'marketplace, so they can already have figures even if you '
            'have not sold anything yet.',
            style: GoogleFonts.montserrat(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          for (final item in kMarketGuideItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FAF5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: GoogleFonts.montserrat(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            item.scope,
                            style: GoogleFonts.montserrat(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.dark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        height: 1.4,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        AgriDialogButton(
          label: 'Got it',
          kind: AgriButtonKind.primary,
          onPressed: () => Navigator.pop(dialogContext),
        ),
      ],
    ),
  );
}
