import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/commodity_master_list.dart';
import '../theme/app_theme.dart';

/// The full, always-up-to-date Supported Products list — reads straight
/// from kCommodityMasterList (the single source of truth) so this list can
/// never drift out of sync with what Add Product's autocomplete and the AI
/// price guide actually recognize. Opened from: the Farmer setup "Supported
/// Products in AgriTrade+" section, the Add Product top banner, and the
/// "unsupported product" dialog.
class SupportedProductsScreen extends StatelessWidget {
  const SupportedProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        backgroundColor: AppTheme.dark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Supported Products', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 17)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Text(
            'AgriTrade+ currently supports selected agricultural commodities based on '
            'the products identified with the agricultural office. Only products on '
            'this list can be posted in the marketplace.',
            style: GoogleFonts.montserrat(fontSize: 13, color: Colors.black87, height: 1.5),
          ),
          const SizedBox(height: 20),
          for (final entry in kCommodityMasterList.entries) ...[
            Text(
              entry.key,
              style: GoogleFonts.montserrat(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppTheme.dark),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: entry.value
                  .map((name) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.mid.withValues(alpha: 0.35)),
                        ),
                        child: Text(name, style: GoogleFonts.montserrat(fontSize: 13, color: Colors.black87)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
          ],
          Text(
            'This list may be updated in the future based on the agricultural '
            'office/client and the approved system scope.',
            style: GoogleFonts.montserrat(fontSize: 11.5, color: Colors.black45, height: 1.4),
          ),
        ],
      ),
    );
  }
}
