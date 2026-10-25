import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../l10n/tr.dart';
import 'agri_app_bar.dart';

/// The shared frame of the Farmer Dashboard's market cards (Best-Selling
/// Products, Top Buyer Locations, Current Market Average):
/// the title with a line under it saying what is counted, an optional
/// [tag] on the right (the month shown), then the card's own content.
class MarketCardShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? tag;
  final Widget child;

  const MarketCardShell({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.tag,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE9F0E4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.montserrat(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: GoogleFonts.montserrat(
                          fontSize: 11.5,
                          height: 1.35,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (tag != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    tag!,
                    style: GoogleFonts.montserrat(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.dark,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// What a market card shows when it has nothing to list yet.
class MarketCardEmpty extends StatelessWidget {
  final IconData icon;
  final String message;

  const MarketCardEmpty({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: AppTheme.dark.withValues(alpha: 0.45)),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

/// The thin bar a market card shows while its data is loading.
class MarketCardLoading extends StatelessWidget {
  const MarketCardLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        minHeight: 2.5,
        color: AppTheme.dark.withValues(alpha: 0.55),
        backgroundColor: AppTheme.dark.withValues(alpha: 0.08),
      ),
    );
  }
}

/// How many rows a market card lists on the dashboard; the rest are on its
/// own full-list screen (see [MarketCardViewAll]).
const int kMarketCardRows = 5;

/// The rows a market card lists: all of them on its full-list screen
/// ([showAll]), else the first [kMarketCardRows], then "View all (N)" —
/// opening that screen via [openAll] — when there are more.
Widget marketCardRows({
  required List<Widget> rows,
  required bool showAll,
  required VoidCallback openAll,
}) {
  final shown = showAll ? rows : rows.take(kMarketCardRows).toList();
  return Column(
    children: [
      // One plain line each, a hairline between them — easy to scan.
      for (var i = 0; i < shown.length; i++) ...[
        if (i > 0) Divider(height: 1, color: Colors.grey[200]),
        shown[i],
      ],
      if (!showAll && rows.length > kMarketCardRows)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: MarketCardViewAll(count: rows.length, onPressed: openAll),
        ),
    ],
  );
}

/// Opens the full-list screen of a market card whose list is too long for
/// the dashboard: [child] — the same card, showing every row — under an
/// app bar titled [title].
void openMarketCardScreen(
  BuildContext context, {
  required String title,
  required Widget child,
}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: AppTheme.surface,
        appBar: AgriAppBar(title: title),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// "View all (N)" under a market card's first rows; opens its full list.
class MarketCardViewAll extends StatelessWidget {
  final int count;
  final VoidCallback onPressed;

  const MarketCardViewAll({
    super.key,
    required this.count,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: TextButton.icon(
        onPressed: onPressed,
        iconAlignment: IconAlignment.end,
        icon: const Icon(Icons.chevron_right_rounded, size: 18),
        label: Text('${tr(context).viewAll} ($count)'),
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.dark,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: GoogleFonts.montserrat(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
