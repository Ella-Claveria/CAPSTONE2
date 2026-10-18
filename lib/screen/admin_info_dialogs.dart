import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/legal_policies.dart';
import '../theme/app_theme.dart';
import 'admin_dashboard_screen.dart' show AdminPalette, AdminThemeScope;
import 'admin_help_center.dart' show showAdminHelpCenter;

// The Admin menu's information popups: Terms & Privacy, Help & Support
// (admin_help_center.dart) and About AgriTrade+. All static — nothing here reads or
// writes data of its own. A popup is outside the portal's AdminThemeScope,
// so each is handed the palette.

/// The same dialog frame for each: title, a close button, the content, and
/// Close at the foot.
Future<void> _showInfoDialog(
  BuildContext context, {
  required String title,
  required Widget Function(AdminPalette c) content,
  double width = 560,
}) {
  final palette = AdminThemeScope.of(context).palette;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      // On a short or narrow window the content scrolls instead of
      // overflowing.
      scrollable: true,
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      title: Row(children: [Expanded(child: Text(title))]),
      content: SizedBox(width: width, child: content(palette)),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Widget _paragraph(AdminPalette c, String text) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Text(
    text,
    style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.5),
  ),
);

/// An amber "needs review" box: information the project does not have yet.
Widget _reviewNote(AdminPalette c, String title, List<String> lines) =>
    Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: c.amberBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded, size: 18, color: c.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $line',
                style: TextStyle(color: c.textSecondary, fontSize: 12.5),
              ),
            ),
        ],
      ),
    );

// ---- Terms & Privacy ----

/// Admin menu → Terms & Privacy: the Terms of Service and Privacy Policy
/// that farmers and buyers agree to at registration (the same text,
/// lib/data/legal_policies.dart), and the Administrator Guidelines, which
/// only administrators see. One tab each; the title, the tabs and Close stay
/// in place while the text scrolls. Reading them here is not anyone's
/// acceptance: farmers and buyers accept at registration.
Future<void> showAdminTermsPrivacy(BuildContext context) {
  final palette = AdminThemeScope.of(context).palette;
  return showDialog<void>(
    context: context,
    builder: (_) => _TermsPrivacyDialog(palette: palette),
  );
}

class _TermsPrivacyDialog extends StatelessWidget {
  final AdminPalette palette;
  const _TermsPrivacyDialog({required this.palette});

  static const _documents = [
    (tab: 'Terms of Service', doc: kTermsOfService, internal: false),
    (tab: 'Privacy Policy', doc: kPrivacyPolicy, internal: false),
    (tab: 'Admin Guidelines', doc: kAdminGuidelines, internal: true),
  ];

  @override
  Widget build(BuildContext context) {
    final c = palette;
    final size = MediaQuery.sizeOf(context);
    // Most of a small window, at most 760 × 720.
    final width = math.min(760.0, size.width - 32);
    final height = math.min(720.0, size.height - 48);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SizedBox(
        width: width,
        height: height,
        child: DefaultTabController(
          length: _documents.length,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 14, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Terms & Privacy',
                        style: TextStyle(
                          color: AppTheme.dark,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              TabBar(
                isScrollable: width < 520,
                tabAlignment: width < 520 ? TabAlignment.start : null,
                labelColor: AppTheme.dark,
                unselectedLabelColor: c.textSecondary,
                indicatorColor: AppTheme.dark,
                indicatorSize: TabBarIndicatorSize.label,
                dividerColor: c.border,
                labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                tabs: [for (final d in _documents) Tab(text: d.tab)],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final d in _documents)
                      _PolicyView(
                        palette: c,
                        document: d.doc,
                        internal: d.internal,
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: c.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Draft for review before production use.',
                        style: TextStyle(color: c.textMuted, fontSize: 11.5),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One policy, scrolling on its own: title, version and dates, intro, the
/// draft notice, then its sections.
class _PolicyView extends StatefulWidget {
  final AdminPalette palette;
  final PolicyDocument document;

  /// The Administrator Guidelines: for administrators only.
  final bool internal;

  const _PolicyView({
    required this.palette,
    required this.document,
    required this.internal,
  });

  @override
  State<_PolicyView> createState() => _PolicyViewState();
}

class _PolicyViewState extends State<_PolicyView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.palette;
    final doc = widget.document;

    Widget chip(IconData icon, String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c.textSecondary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: TextStyle(color: c.textSecondary, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );

    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
        children: [
          Text(
            doc.title,
            style: const TextStyle(
              color: AppTheme.dark,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              chip(Icons.event_available_outlined, doc.effectiveLabel),
              chip(Icons.update_rounded, doc.updatedLabel),
              chip(Icons.tag_rounded, 'Version ${doc.version}'),
            ],
          ),
          const SizedBox(height: 12),
          _paragraph(c, doc.intro),
          const SizedBox(height: 4),
          _reviewNote(
            c,
            widget.internal
                ? 'Internal — for administrators only'
                : 'Draft for the capstone project',
            [
              if (widget.internal)
                'Not shown to farmers or buyers, and not part of the public '
                    'Terms of Service.',
              'Review against the system\'s actual behaviour and the '
                  'Philippine Data Privacy Act before production use.',
              'Text in [square brackets] still needs approval.',
            ],
          ),
          for (final section in doc.sections) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 6),
              child: Text(
                section.heading,
                style: const TextStyle(
                  color: AppTheme.dark,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final paragraph in section.paragraphs)
              _paragraph(c, paragraph),
            for (final point in section.points)
              Padding(
                padding: const EdgeInsets.only(bottom: 5, left: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7, right: 10),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: AppTheme.dark,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        point,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ---- Help & Support ----

/// Admin menu → Help & Support: the FAQ and FAQ
/// Management (admin_help_center.dart).
Future<void> showAdminHelp(BuildContext context) =>
    showAdminHelpCenter(context);

// ---- About AgriTrade+ ----

// Read once for the app's lifetime — it cannot change while running.
final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

/// Admin menu → About AgriTrade+: the logo and what the platform is, its
/// two parts (the mobile app and this portal), and the project details,
/// with the version of this build.
Future<void> showAdminAbout(BuildContext context) {
  return _showInfoDialog(
    context,
    title: 'About AgriTrade+',
    width: 520,
    content: (c) {
      Widget component(IconData icon, String title, String text) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.greenBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 19, color: AppTheme.dark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.dark,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    text,
                    style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

      Widget detail(String label, String value, {bool placeholder = false}) =>
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    label,
                    style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      color: placeholder ? c.textMuted : c.textPrimary,
                      fontSize: 12.5,
                      fontWeight: placeholder
                          ? FontWeight.w500
                          : FontWeight.w600,
                      fontStyle: placeholder ? FontStyle.italic : null,
                    ),
                  ),
                ),
              ],
            ),
          );

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Center(
            child: Image.asset(
              'assets/images/logo.png',
              height: 64,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  Icon(Icons.agriculture_rounded, color: c.green, size: 56),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text('AgriTrade+', style: AppTheme.brandText(fontSize: 22)),
          ),
          const SizedBox(height: 2),
          Text(
            'Agricultural & Livestock Trading Platform',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          // What is built: listings, messages, orders and the price
          // suggestion the app labels "AI-Assisted".
          Text(
            'AgriTrade+ is a digital marketplace that connects farmers, '
            'livestock raisers, and buyers. It supports agricultural and '
            'livestock product listings, buyer-seller communication, order '
            'management, and AI-assisted price recommendations to help users '
            'make informed trading decisions.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 14),
          // Side by side where there is room; one under the other on a
          // narrow window.
          Builder(
            builder: (context) {
              final mobile = component(
                Icons.phone_android_rounded,
                'Mobile Application',
                'For farmers, livestock raisers, and buyers.',
              );
              final portal = component(
                Icons.admin_panel_settings_outlined,
                'Admin Portal',
                'For authorized user management, platform monitoring, and '
                    'administration.',
              );
              if (MediaQuery.sizeOf(context).width < 600) {
                return Column(
                  children: [mobile, const SizedBox(height: 8), portal],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: mobile),
                    const SizedBox(width: 8),
                    Expanded(child: portal),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: c.border),
          const SizedBox(height: 10),
          // The real version of this build.
          FutureBuilder<PackageInfo>(
            future: _packageInfo,
            builder: (context, snapshot) {
              final version = snapshot.data?.version ?? '';
              return detail('Version', version.isEmpty ? '—' : version);
            },
          ),
        ],
      );
    },
  );
}
