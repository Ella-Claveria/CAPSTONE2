import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/legal_policies.dart';
import '../theme/app_theme.dart';
import '../widgets/agri_app_bar.dart';

/// One policy from lib/data/legal_policies.dart as a full page of the
/// mobile app: its title, version and dates, then each section. Used for
/// the Terms of Service and the Privacy Policy, opened from registration
/// and from Settings.
class PolicyDocumentScreen extends StatelessWidget {
  final PolicyDocument document;
  const PolicyDocumentScreen({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    TextStyle body({Color color = Colors.black87, double size = 12.5}) =>
        GoogleFonts.montserrat(fontSize: size, color: color, height: 1.5);

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AgriAppBar(title: document.title),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Text(
            'AgriTrade+ ${document.title}',
            style: GoogleFonts.montserrat(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${document.effectiveLabel}\n${document.updatedLabel}',
            style: body(color: Colors.black54, size: 11.5),
          ),
          const SizedBox(height: 12),
          Text(document.intro, style: body(color: Colors.black54)),
          const SizedBox(height: 20),
          for (final section in document.sections) ...[
            Text(
              section.heading,
              style: GoogleFonts.montserrat(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
                color: AppTheme.dark,
              ),
            ),
            const SizedBox(height: 6),
            for (final paragraph in section.paragraphs)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 2),
                child: Text(paragraph, style: body()),
              ),
            for (final point in section.points)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: body(color: AppTheme.dark)),
                    Expanded(child: Text(point, style: body())),
                  ],
                ),
              ),
            const SizedBox(height: 14),
          ],
          Text(
            'Version ${document.version}',
            style: body(color: Colors.black38, size: 11),
          ),
        ],
      ),
    );
  }
}
