import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// One option on the buyer's Profile tab (My Reviews, Liked Products…):
/// a plain row — icon, label, chevron — with a hairline under it, the same
/// look as the Manage Account list (no card per option).
///
/// [destructive] is for Log Out: red, with no chevron and no hairline.
class ProfileLinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const ProfileLinkTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.red.shade700 : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          leading: Icon(icon, color: color ?? AppTheme.dark),
          title: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: destructive ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
          trailing: destructive
              ? null
              : const Icon(Icons.chevron_right, color: Colors.grey),
          onTap: onTap,
        ),
        if (!destructive)
          Divider(
            height: 1,
            indent: 20,
            endIndent: 20,
            color: Colors.grey[200],
          ),
      ],
    );
  }
}

/// A small grey heading over a group of Profile options — the divisions
/// of the list, not cards.
class ProfileSectionLabel extends StatelessWidget {
  final String text;
  const ProfileSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.montserrat(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: Colors.grey[600],
        ),
      ),
    ),
  );
}
