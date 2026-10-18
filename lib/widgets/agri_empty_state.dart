import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// The one "nothing here yet" look for the mobile app: a small dark-green
/// icon on a pale-green circle, a title, an optional line under it and an
/// optional action. Every empty list — orders, messages, notifications,
/// reviews, search results — uses this, so they all match.
class AgriEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  /// Space around the content. The default suits a full page; a list
  /// inside a card passes something tighter.
  final EdgeInsetsGeometry padding;

  const AgriEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: AppTheme.tint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: AppTheme.dark),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 12.5,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
