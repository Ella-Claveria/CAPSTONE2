import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/mobile_faqs.dart';
import '../theme/app_theme.dart';
import '../widgets/agri_app_bar.dart';
import 'buyer_support_screen.dart';
import '../l10n/tr.dart';

/// Help & Support for the mobile app, from the Profile tab's settings
/// menu: the FAQ for the user's role (tap a question to open its answer),
/// then how to reach the AgriTrade+ team — the support email (copy it or
/// open the mail app) and a support request sent from the app.
class HelpSupportScreen extends StatelessWidget {
  final bool farmer;

  const HelpSupportScreen({super.key, required this.farmer});

  @override
  Widget build(BuildContext context) {
    final faqs = mobileFaqsFor(farmer: farmer);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AgriAppBar(title: tr(context).helpSupport),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _label(tr(context).faqTitle),
            for (var i = 0; i < faqs.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: Colors.grey[200],
                ),
              _FaqTile(faq: faqs[i]),
            ],
            const SizedBox(height: 10),
            _label(tr(context).contactUs),
            const _ContactEmail(),
            ListTile(
              leading: const Icon(
                Icons.support_agent_outlined,
                color: AppTheme.dark,
              ),
              title: Text(tr(context).sendSupportRequest),
              subtitle: Text(tr(context).supportRequestHint),
              trailing: Icon(Icons.chevron_right, color: Colors.grey[500]),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BuyerSupportScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text.toUpperCase(),
      style: GoogleFonts.montserrat(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: Colors.grey[600],
      ),
    ),
  );
}

/// One question; tapping it opens the answer under it.
class _FaqTile extends StatelessWidget {
  final MobileFaq faq;
  const _FaqTile({required this.faq});

  @override
  Widget build(BuildContext context) => Theme(
    // No lines above and below an open tile — the dividers do that.
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      iconColor: AppTheme.dark,
      collapsedIconColor: Colors.grey[500],
      expandedAlignment: Alignment.centerLeft,
      title: Text(
        faq.question,
        style: GoogleFonts.montserrat(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      children: [
        Text(
          faq.answer,
          style: GoogleFonts.montserrat(
            fontSize: 12.5,
            height: 1.5,
            color: Colors.grey[700],
          ),
        ),
      ],
    ),
  );
}

/// The support email, with Copy and a button that opens the mail app.
class _ContactEmail extends StatelessWidget {
  const _ContactEmail();

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.mail_outline_rounded, color: AppTheme.dark),
    title: const Text(kSupportEmail),
    subtitle: const Text('Email the AgriTrade+ team'),
    onTap: () => _email(context),
    trailing: IconButton(
      tooltip: 'Copy email',
      icon: Icon(Icons.copy_rounded, size: 20, color: Colors.grey[600]),
      onPressed: () async {
        await Clipboard.setData(const ClipboardData(text: kSupportEmail));
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Email copied.')));
      },
    ),
  );

  Future<void> _email(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    bool opened;
    try {
      opened = await launchUrl(
        Uri(
          scheme: 'mailto',
          path: kSupportEmail,
          query: 'subject=${Uri.encodeComponent('AgriTrade+ Support')}',
        ),
      );
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No email app found. The address can be copied.'),
        ),
      );
    }
  }
}
