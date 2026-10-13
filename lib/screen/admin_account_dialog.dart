import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/dashboard_data_service.dart';
import '../services/moderation_model.dart';
import 'admin_dashboard_screen.dart' show AdminPalette, AdminStatusBadge;
import 'admin_filter_controls.dart';
import 'admin_user_accounts_view.dart';
import 'moderation_queue_view.dart' show showAdminReportDialog;

// One user's account as the Admin sees it — opened from User Accounts and
// from a report's "Reported User" — and that same user's moderation
// history. Both read the portal's shared live lists of users and reports
// and pick the one account out by its uid: nothing is copied, so a report
// and the account it is about can never drift apart.
//
// A popup is outside the portal's AdminThemeScope, so the palette is
// handed in.

/// Clear = subtle green, Reported = light orange, Under Review = orange,
/// Confirmed Violation = red.
Widget adminModerationBadge(AdminPalette c, ModerationStatus status) {
  const orange = Color(0xFFC2410C);
  final (color, bg) = switch (status) {
    ModerationStatus.clear => (c.green, c.greenBg),
    ModerationStatus.reported => (c.amber, c.amberBg),
    ModerationStatus.underReview => (
      c.isDark ? const Color(0xFFFDBA74) : orange,
      orange.withValues(alpha: c.isDark ? 0.30 : 0.16),
    ),
    ModerationStatus.confirmedViolation => (c.red, c.redBg),
  };
  return AdminStatusBadge(text: status.label, color: color, bg: bg);
}

/// Active = green, Suspended = orange, Banned = red, Deactivated = gray.
Widget adminAccountStatusBadge(AdminPalette c, String status) {
  final (color, bg) = switch (status) {
    'active' => (c.green, c.greenBg),
    'suspended' => (c.amber, c.amberBg),
    'banned' => (c.red, c.redBg),
    _ => (c.textSecondary, c.surfaceAlt),
  };
  return AdminStatusBadge(
    text: accountStatusLabel(status),
    color: color,
    bg: bg,
  );
}

String _shortId(String id) => id.length > 8 ? id.substring(0, 8) : id;

String _when(dynamic value) => value is Timestamp
    ? DateFormat('MMM d, y – h:mm a').format(value.toDate())
    : '—';

/// The user's current profile photo, or their initials: see [AdminAvatar].
Widget adminUserAvatar(
  AdminPalette c, {
  required String name,
  String? photoUrl,
  double radius = 22,
}) => AdminAvatar(name: name, photoUrl: photoUrl, radius: radius);

Widget _section(AdminPalette c, String label) => Padding(
  padding: const EdgeInsets.only(top: 14, bottom: 6),
  child: Text(
    label.toUpperCase(),
    style: TextStyle(
      color: c.textMuted,
      fontSize: 11,
      letterSpacing: 0.6,
      fontWeight: FontWeight.w700,
    ),
  ),
);

Widget _row(AdminPalette c, String label, Widget value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 5),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 170,
        child: Text(
          label,
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      Expanded(
        child: DefaultTextStyle.merge(
          style: TextStyle(color: c.textPrimary, fontSize: 13),
          child: Align(alignment: Alignment.centerLeft, child: value),
        ),
      ),
    ],
  ),
);

/// Opens the account of the user with this [uid]: who they are, whether
/// the account can be used, and where it stands with moderation.
Future<void> showAdminAccountDialog(
  BuildContext context, {
  required AdminPalette palette,
  required String uid,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AccountDialog(palette: palette, uid: uid),
  );
}

class _AccountDialog extends StatelessWidget {
  final AdminPalette palette;
  final String uid;
  const _AccountDialog({required this.palette, required this.uid});

  @override
  Widget build(BuildContext context) {
    final c = palette;
    final data = DashboardDataService.instance;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: data.usersStream,
      builder: (context, users) =>
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: data.allReportsStream,
            builder: (context, reports) {
              Widget shell(Widget content, {List<Widget> more = const []}) =>
                  AlertDialog(
                    title: const Text('User Account'),
                    content: SizedBox(width: 520, child: content),
                    actions: [
                      ...more,
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  );

              if (users.hasError) {
                return shell(const Text('This account could not be loaded.'));
              }
              if (!users.hasData) {
                return shell(
                  const SizedBox(
                    height: 120,
                    child: Center(child: AdminLoadingBar()),
                  ),
                );
              }
              Map<String, dynamic>? user;
              for (final doc in users.data!.docs) {
                if (doc.id == uid) user = doc.data();
              }
              final row = user == null
                  ? null
                  : AdminAccountRow.fromUser(uid, user);
              if (user == null || row == null) {
                return shell(
                  const Text(
                    'No buyer or farmer account has this ID. It may have been '
                    'removed.',
                  ),
                );
              }

              // Counted from the reports about this exact account.
              final summary = reports.hasData
                  ? (summarizeModeration([
                          for (final doc in reports.data!.docs) doc.data(),
                        ])[uid] ??
                        ModerationSummary.none)
                  : null;
              final name = row.name.isEmpty ? 'Unnamed account' : row.name;

              return shell(
                SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          adminUserAvatar(
                            c,
                            name: name,
                            photoUrl: user['photoUrl']?.toString(),
                            radius: 26,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${row.isBuyer ? 'Buyer' : 'Farmer'} · '
                                  'ID ${_shortId(uid)}',
                                  style: TextStyle(
                                    color: c.textSecondary,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      _section(c, 'Account Information'),
                      _row(c, 'Name', Text(name)),
                      _row(c, 'Role', Text(row.isBuyer ? 'Buyer' : 'Farmer')),
                      _row(
                        c,
                        'Email',
                        Text(row.email.isEmpty ? '—' : row.displayEmail),
                      ),
                      _row(
                        c,
                        'General Area',
                        Text(row.area.isEmpty ? 'Not saved' : row.area),
                      ),
                      _row(
                        c,
                        'Date Registered',
                        Text(
                          row.registered == null
                              ? '—'
                              : DateFormat('MMM d, y').format(row.registered!),
                        ),
                      ),
                      _row(
                        c,
                        'Email Verification',
                        Text(row.emailVerified ? 'Verified' : 'Not verified'),
                      ),
                      if (row.identity != null)
                        _row(
                          c,
                          'Farmer Verification',
                          Text(switch (row.identity!) {
                            AccountIdentity.verified => 'Approved',
                            AccountIdentity.pendingReview => 'Pending review',
                            AccountIdentity.rejected => 'Rejected',
                          }),
                        ),
                      _row(
                        c,
                        'Account Status',
                        adminAccountStatusBadge(c, row.accountStatus),
                      ),
                      _section(c, 'Moderation Summary'),
                      if (summary == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: AdminLoadingBar(),
                        )
                      else ...[
                        _row(
                          c,
                          'Moderation Status',
                          adminModerationBadge(c, summary.status),
                        ),
                        _row(
                          c,
                          'Reports Received',
                          Text('${summary.reportsReceived}'),
                        ),
                        _row(
                          c,
                          'Reports Under Review',
                          Text('${summary.underReview}'),
                        ),
                        _row(
                          c,
                          'Confirmed Violations',
                          Text('${summary.confirmedViolations}'),
                        ),
                        _row(c, 'Warnings Issued', Text('${summary.warnings}')),
                      ],
                    ],
                  ),
                ),
                more: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text('View Moderation History'),
                    onPressed: () => showAdminModerationHistory(
                      context,
                      palette: c,
                      uid: uid,
                      name: name,
                    ),
                  ),
                ],
              );
            },
          ),
    );
  }
}

/// The reports filed about the user with this [uid], and the violations
/// confirmed from them. Each opens the report it is.
Future<void> showAdminModerationHistory(
  BuildContext context, {
  required AdminPalette palette,
  required String uid,
  required String name,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        _ModerationHistoryDialog(palette: palette, uid: uid, name: name),
  );
}

class _ModerationHistoryDialog extends StatelessWidget {
  final AdminPalette palette;
  final String uid;
  final String name;
  const _ModerationHistoryDialog({
    required this.palette,
    required this.uid,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    final c = palette;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: DashboardDataService.instance.allReportsStream,
      builder: (context, snapshot) {
        final Widget content;
        if (snapshot.hasError) {
          content = const Text('The moderation history could not be loaded.');
        } else if (!snapshot.hasData) {
          content = const SizedBox(
            height: 120,
            child: Center(child: AdminLoadingBar()),
          );
        } else {
          final reports =
              [
                for (final doc in snapshot.data!.docs)
                  if (reportedUserIdOf(doc.data()) == uid) doc,
              ]..sort((a, b) {
                final at = a.data()['createdAt'];
                final bt = b.data()['createdAt'];
                return (bt is Timestamp ? bt.millisecondsSinceEpoch : 0)
                    .compareTo(at is Timestamp ? at.millisecondsSinceEpoch : 0);
              });
          final violations = [
            for (final doc in reports)
              if (doc.data()['violationConfirmed'] == true) doc,
          ];

          Widget entry(
            QueryDocumentSnapshot<Map<String, dynamic>> doc, {
            required bool asViolation,
          }) {
            final report = doc.data();
            final decision = reportDecisionOf(report);
            final reason =
                (report['issueType'] ?? report['reason'] ?? 'General Report')
                    .toString();
            final stage = reportStageOf(report);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  // The violation's source report, or the report itself.
                  onTap: () => showAdminReportDialog(
                    context,
                    palette: c,
                    reportId: doc.id,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                reason,
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                asViolation
                                    ? 'Source report ${_shortId(doc.id)} · '
                                          '${decision == null ? 'Violation confirmed' : _decisionLabel(decision)} · '
                                          '${_when(report['reviewedAt'])}'
                                    : 'Report ${_shortId(doc.id)} · '
                                          '${_when(report['createdAt'])}',
                                style: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (!asViolation)
                          adminModerationBadge(
                            c,
                            report['violationConfirmed'] == true
                                ? ModerationStatus.confirmedViolation
                                : stage == 'under_review'
                                ? ModerationStatus.underReview
                                : stage == 'pending'
                                ? ModerationStatus.reported
                                : ModerationStatus.clear,
                          ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: c.textMuted,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          content = reports.isEmpty
              ? Text(
                  'No report has been filed about this account.',
                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _section(
                        c,
                        'Confirmed Violations (${violations.length})',
                      ),
                      if (violations.isEmpty)
                        Text(
                          'None confirmed.',
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      for (final doc in violations)
                        entry(doc, asViolation: true),
                      _section(c, 'Reports (${reports.length})'),
                      for (final doc in reports) entry(doc, asViolation: false),
                    ],
                  ),
                );
        }
        return AlertDialog(
          title: Text('$name — Moderation History'),
          content: SizedBox(width: 520, child: content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

/// A report's recorded decision in words.
String _decisionLabel(String decision) => switch (decision) {
  'violation_recorded' => 'Violation recorded',
  'warning' => 'Warning issued',
  'hidden' => 'Listing hidden',
  'removed' => 'Listing removed',
  'review_removed' => 'Review removed',
  'suspended' => 'Account suspended',
  'banned' => 'Account banned',
  'dismissed' => 'Report dismissed',
  'no_violation' => 'Resolved, no violation',
  _ => decision,
};

/// See [_decisionLabel]; shared with the Moderation Queue.
String adminDecisionLabel(String decision) => _decisionLabel(decision);
