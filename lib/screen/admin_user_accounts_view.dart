import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/audit_log_service.dart';
import '../services/auth_routing_service.dart' show suspensionEndOf;
import '../services/connectivity_service.dart';
import '../services/dashboard_data_service.dart';
import '../services/moderation_model.dart';
import 'admin_account_dialog.dart';
import 'admin_dashboard_screen.dart'
    show
        AdminThemeScope,
        AdminPalette,
        AdminEmptyState,
        AdminLoadingSpinner,
        AdminStatusBadge,
        AdminStreamError;
import 'admin_filter_controls.dart';

/// Where a farmer's application stands. Buyers have no application: their
/// account is verified by email alone.
enum AccountIdentity {
  /// A farmer whose credentials were approved.
  verified,

  /// A farmer whose application is waiting in the Verification Queue.
  pendingReview,

  /// A farmer whose application was rejected.
  rejected,
}

/// One marketplace account (buyer or farmer), as User Accounts shows it.
class AdminAccountRow {
  final String uid;
  final String name;
  final String email;
  final String role;
  final String area;
  final bool emailVerified;

  /// Null for a buyer.
  final AccountIdentity? identity;
  final String accountStatus;
  final DateTime? registered;

  /// The account's current profile photo (the one the mobile app shows
  /// and updates); empty when none has been uploaded.
  final String photoUrl;

  /// When a suspension set for a time ends; null for one that lasts until
  /// an Admin reactivates the account (or for an account not suspended).
  final DateTime? suspendedUntil;

  /// Why the account is suspended; empty when it is not.
  final String suspensionReason;

  const AdminAccountRow({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.area,
    required this.emailVerified,
    required this.identity,
    required this.accountStatus,
    required this.registered,
    this.photoUrl = '',
    this.suspendedUntil,
    this.suspensionReason = '',
  });

  bool get isBuyer => role == 'buyer';

  /// The email as the table shows it. A buyer's is partly hidden — the
  /// Admin monitors buyer accounts but has no need for their contact
  /// details — while a farmer's, part of the application the Admin
  /// reviewed, is shown in full.
  String get displayEmail => isBuyer ? maskEmail(email) : email;

  /// Null for an account that is not a marketplace user (an Admin).
  static AdminAccountRow? fromUser(String uid, Map<String, dynamic> data) {
    final role = (data['role'] ?? '').toString().toLowerCase();
    if (role != 'buyer' && role != 'farmer') return null;

    String text(List<String> keys) {
      for (final key in keys) {
        final value = (data[key] ?? '').toString().trim();
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    // A farmer's identity is what the Verification Queue decides.
    AccountIdentity? identity;
    if (role == 'farmer') {
      final approval = (data['approvalStatus'] ?? 'pending')
          .toString()
          .toLowerCase();
      identity = approval == 'approved'
          ? AccountIdentity.verified
          : approval == 'rejected'
          ? AccountIdentity.rejected
          : AccountIdentity.pendingReview;
    }

    final created = data['createdAt'];
    return AdminAccountRow(
      uid: uid,
      name: text(['fullName', 'name']),
      email: text(['email']),
      role: role,
      area: [
        text(['barangay']),
        text(['municipality', 'province']),
      ].where((s) => s.isNotEmpty).join(', '),
      // The app's own email code, a verified email link, or a Google
      // sign-in (whose address Google has already verified).
      emailVerified:
          data['emailOtpVerified'] == true ||
          data['emailVerified'] == true ||
          (data['authProvider'] ?? '').toString() == 'google',
      identity: identity,
      accountStatus: (data['accountStatus'] ?? 'active')
          .toString()
          .toLowerCase(),
      registered: created is Timestamp ? created.toDate() : null,
      photoUrl: text(['photoUrl']),
      suspendedUntil: suspensionEndOf(data),
      suspensionReason: text(['suspensionReason']),
    );
  }

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    // A buyer is found by the email as shown, so a search cannot be used
    // to work out the hidden part.
    return name.toLowerCase().contains(q) ||
        displayEmail.toLowerCase().contains(q) ||
        area.toLowerCase().contains(q) ||
        uid.toLowerCase().contains(q);
  }
}

/// "pes***@gmail.com": the first three characters of an email's name and
/// its domain, the rest hidden. Text that is not an email is hidden
/// entirely.
String maskEmail(String email) {
  final at = email.lastIndexOf('@');
  if (email.isEmpty) return '';
  if (at <= 0) return '***';
  final name = email.substring(0, at);
  final shown = name.length <= 3 ? name.substring(0, 1) : name.substring(0, 3);
  return '$shown***${email.substring(at)}';
}

/// Every buyer and farmer account, newest first. Pure, so it can be tested
/// without Firestore.
List<AdminAccountRow> buildAccountRows(
  Iterable<({String id, Map<String, dynamic> data})> users,
) {
  final rows = [
    for (final user in users) ?AdminAccountRow.fromUser(user.id, user.data),
  ];
  rows.sort((a, b) {
    final at = a.registered?.millisecondsSinceEpoch ?? 0;
    final bt = b.registered?.millisecondsSinceEpoch ?? 0;
    return bt.compareTo(at);
  });
  return rows;
}

/// Reports against an account before Suspend Accounts flags it for
/// review (the Admin can still suspend any account).
const int kSuspendReportThreshold = 10;

/// How long a suspension lasts: a set time, or until an Admin reactivates
/// the account ([duration] null).
typedef SuspensionLength = ({String label, Duration? duration});

/// The lengths Suspend offers, 24 hours first (the default).
const List<SuspensionLength> kSuspensionLengths = [
  (label: '24 hours', duration: Duration(hours: 24)),
  (label: '3 days', duration: Duration(days: 3)),
  (label: '7 days', duration: Duration(days: 7)),
  (label: '30 days', duration: Duration(days: 30)),
  (label: 'Until reactivated', duration: null),
];

/// Reasons to start from; the Admin can edit or write their own.
const List<String> kSuspensionReasons = [
  'Many reports from other users',
  'Scam or fraudulent transactions',
  'Abusive or harassing messages',
  'Fake or misleading listings',
];

/// "Suspended until Oct 17, 2026 · 10:51 AM", or until reactivated.
String suspensionUntilLabel(DateTime? until) => until == null
    ? 'Until an Admin reactivates it'
    : 'Until ${DateFormat('MMM d, y · h:mm a').format(until)}';

/// Suspends the accounts given that are active (asking for the reason and
/// how long first), or reactivates the ones that are suspended or
/// deactivated. True when it was done. With [reports], the number of
/// reports against each account (by uid), shown when there is one.
///
/// A suspended account is told why and until when: by push and email
/// (functions/index.js, account_emails.js), and with the notice it gets
/// when it tries to log in or is signed in (AuthRoutingService,
/// AccountStatusWatcher). A suspension for a set time ends by itself
/// (functions/suspension.js).
// A ban is decided on a report,
// one account at a time, and is not undone from here. Nothing is ever
// deleted: orders, reports and reviews keep pointing at a real account.
Future<bool> adminSetAccountsSuspended(
  BuildContext context,
  List<AdminAccountRow> selected, {
  required bool suspend,
  Map<String, int> reports = const {},
}) async {
  final targets = [
    for (final row in selected)
      if (suspend
          ? row.accountStatus == 'active'
          : row.accountStatus == 'suspended' ||
                row.accountStatus == 'deactivated')
        row,
  ];
  if (targets.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          suspend
              ? 'None of the selected accounts is active.'
              : 'None of the selected accounts is suspended.',
        ),
      ),
    );
    return false;
  }
  final label = targets.length == 1
      ? (targets.single.name.isEmpty ? 'this account' : targets.single.name)
      : '${targets.length} accounts';
  final skipped = selected.length - targets.length;
  // A dialog sits outside the page's AdminThemeScope: hand the palette in.
  final palette =
      context.getInheritedWidgetOfExactType<AdminThemeScope>()?.palette ??
      AdminPalette.light;
  final reportCount = targets.length == 1 ? reports[targets.single.uid] : null;

  final reasonController = TextEditingController();
  final customController = TextEditingController(text: '2');
  var missingReason = false;
  // An index into kSuspensionLengths, or -1 for a custom length.
  var length = 0;
  var customDays = true;
  String? customError;

  Duration? chosenDuration() {
    if (length >= 0) return kSuspensionLengths[length].duration;
    final n = int.tryParse(customController.text.trim());
    if (n == null || n < 1) return null;
    return customDays ? Duration(days: n) : Duration(hours: n);
  }

  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AdminThemeScope(
      palette: palette,
      child: StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final c = palette;
          Widget chip(String text, bool selected, VoidCallback onTap) =>
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? c.greenBg : c.surfaceAlt,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected
                            ? c.green.withValues(alpha: 0.6)
                            : c.border,
                      ),
                    ),
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: selected ? c.green : c.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
          Widget heading(String text) => Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
          );

          final duration = chosenDuration();
          final until = duration == null ? null : DateTime.now().add(duration);

          return AlertDialog(
            title: Text(suspend ? 'Suspend $label?' : 'Reactivate $label?'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suspend
                          ? 'A suspended account cannot log in. It is told '
                                'why and until when, and its orders, '
                                'listings, reports and reviews are kept.'
                          : 'The account will be able to log in again.',
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                    if (suspend && reportCount != null && reportCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          '$reportCount '
                          '${reportCount == 1 ? 'report' : 'reports'} '
                          'against this account.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: reportCount >= kSuspendReportThreshold
                                ? c.red
                                : c.textSecondary,
                          ),
                        ),
                      ),
                    if (skipped > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          suspend
                              ? '$skipped selected '
                                    '${skipped == 1 ? 'account is' : 'accounts are'} '
                                    'not active and will be left as '
                                    '${skipped == 1 ? 'it is' : 'they are'}.'
                              : '$skipped selected '
                                    '${skipped == 1 ? 'account is' : 'accounts are'} '
                                    'not suspended and will be left as '
                                    '${skipped == 1 ? 'it is' : 'they are'}.',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    if (suspend) ...[
                      heading('How long'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < kSuspensionLengths.length; i++)
                            chip(
                              kSuspensionLengths[i].label,
                              length == i,
                              () => setDialogState(() => length = i),
                            ),
                          chip(
                            'Custom',
                            length == -1,
                            () => setDialogState(() => length = -1),
                          ),
                        ],
                      ),
                      if (length == -1)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 90,
                                child: AdminField(
                                  controller: customController,
                                  keyboardType: TextInputType.number,
                                  decoration: adminMultilineDecoration(
                                    dialogContext,
                                    labelText: customDays ? 'Days' : 'Hours',
                                  ),
                                  onChanged: (_) =>
                                      setDialogState(() => customError = null),
                                ),
                              ),
                              const SizedBox(width: 10),
                              chip(
                                'Days',
                                customDays,
                                () => setDialogState(() => customDays = true),
                              ),
                              const SizedBox(width: 6),
                              chip(
                                'Hours',
                                !customDays,
                                () => setDialogState(() => customDays = false),
                              ),
                            ],
                          ),
                        ),
                      if (customError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Text(
                            customError!,
                            style: TextStyle(color: c.red, fontSize: 12),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.event_outlined,
                              size: 16,
                              color: c.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                length == -1 && duration == null
                                    ? 'Enter how long.'
                                    : suspensionUntilLabel(until),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: c.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      heading('Reason (shown to the account)'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final preset in kSuspensionReasons)
                            chip(
                              preset,
                              reasonController.text.trim() == preset,
                              () => setDialogState(() {
                                reasonController.text = preset;
                                missingReason = false;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      AdminField(
                        controller: reasonController,
                        minLines: 2,
                        maxLines: 3,
                        decoration: adminMultilineDecoration(
                          dialogContext,
                          labelText: 'Reason (required)',
                        ),
                        onChanged: (_) => setDialogState(() {
                          missingReason = false;
                        }),
                      ),
                      if (missingReason)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Text(
                            'Give the reason for the suspension.',
                            style: TextStyle(color: c.red, fontSize: 12),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (suspend) {
                    if (length == -1 && chosenDuration() == null) {
                      setDialogState(
                        () => customError = 'Enter a whole number, 1 or more.',
                      );
                      return;
                    }
                    if (reasonController.text.trim().isEmpty) {
                      setDialogState(() => missingReason = true);
                      return;
                    }
                  }
                  Navigator.of(dialogContext).pop(true);
                },
                child: Text(suspend ? 'Suspend' : 'Reactivate'),
              ),
            ],
          );
        },
      ),
    ),
  );
  final reason = reasonController.text.trim();
  final duration = suspend ? chosenDuration() : null;
  if (confirmed != true || !context.mounted) return false;
  if (!await ConnectivityService.instance.checkNow()) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(kNoInternetActionMessage)));
    }
    return false;
  }

  // Counted from when the Admin confirms.
  final until = duration == null ? null : DateTime.now().add(duration);
  try {
    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    final users = FirebaseFirestore.instance.collection('users');
    final batch = FirebaseFirestore.instance.batch();
    for (final row in targets) {
      batch.update(
        users.doc(row.uid),
        suspend
            ? {
                'accountStatus': 'suspended',
                'suspensionReason': reason,
                'suspendedUntil': until == null
                    ? FieldValue.delete()
                    : Timestamp.fromDate(until),
                'moderationUpdatedBy': adminUid,
                'moderationUpdatedAt': FieldValue.serverTimestamp(),
              }
            : {
                'accountStatus': 'active',
                'suspensionReason': FieldValue.delete(),
                'suspendedUntil': FieldValue.delete(),
                'moderationUpdatedBy': adminUid,
                'moderationUpdatedAt': FieldValue.serverTimestamp(),
              },
      );
    }
    await batch.commit();
    AuditLogService.log(
      suspend ? AuditAction.suspendAccount : AuditAction.reactivateAccount,
      '${suspend ? 'Suspended' : 'Reactivated'} '
      '${targets.map((r) => r.name.isEmpty ? r.uid : r.name).join(', ')}'
      '${suspend ? ' (${suspensionUntilLabel(until).toLowerCase()}). Reason: $reason' : '.'}',
    );
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          suspend
              ? 'Suspended $label · ${suspensionUntilLabel(until).toLowerCase()}.'
              : 'Reactivated $label.',
        ),
      ),
    );
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update: $error')));
    }
    return false;
  } finally {
    reasonController.dispose();
    customController.dispose();
  }
}

/// Admin Portal → Verification → User Accounts: every buyer and farmer
/// account with whether its email is verified, for a farmer where their
/// application stands, where the account stands with moderation, and
/// whether it can be used.
///
/// Moderation status and account status are two things. The first is
/// worked out from the reports about the account (see moderation_model):
/// being reported, or even a confirmed violation, does not by itself
/// suspend anyone. The second is what an Admin sets: from the Admin
/// menu's Suspend Accounts, or on a report.
class AdminUserAccountsView extends StatefulWidget {
  /// Buyer accounts only (User Accounts › Buyers): no other tabs, and no
  /// Role or Farmer Application column, which say nothing about a buyer.
  final bool buyersOnly;

  const AdminUserAccountsView({super.key, this.buyersOnly = false});

  @override
  State<AdminUserAccountsView> createState() => _AdminUserAccountsViewState();
}

class _AdminUserAccountsViewState extends State<AdminUserAccountsView>
    with AdminPageSearch {
  // Typed in the header's search box.
  String get _search => pageSearch;

  @override
  void onPageSearchChanged() => _page = 0;

  // The open tab: every account, the buyers, or the farmers whose
  // application is approved, pending or rejected.
  late String _tab = widget.buyersOnly ? 'buyers' : 'all';

  // Rows whose box is ticked, by account id.
  final Set<String> _ticked = {};

  static bool _inTab(AdminAccountRow row, String tab) => switch (tab) {
    'buyers' => row.isBuyer,
    'approved' => row.identity == AccountIdentity.verified,
    'pending' => row.identity == AccountIdentity.pendingReview,
    'rejected' => row.identity == AccountIdentity.rejected,
    _ => true,
  };

  // The open page of the table (10 accounts each), from 0.
  int _page = 0;

  static String identityLabel(AccountIdentity identity) => switch (identity) {
    AccountIdentity.verified => 'Approved',
    AccountIdentity.pendingReview => 'Pending review',
    AccountIdentity.rejected => 'Rejected',
  };

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: DashboardDataService.instance.usersStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const AdminStreamError(source: 'user accounts');
        }
        if (!snapshot.hasData) return const AdminLoadingSpinner();

        final all = buildAccountRows([
          for (final doc in snapshot.data!.docs) (id: doc.id, data: doc.data()),
        ]);
        final filtered = [
          for (final row in all)
            if (_inTab(row, _tab) && row.matches(_search)) row,
        ];
        int count(String tab) => all.where((r) => _inTab(r, tab)).length;
        final selected = [
          for (final row in all)
            if (_ticked.contains(row.uid)) row,
        ];

        // Each account's moderation status, from the reports about it —
        // the same live reports the Moderation Queue shows. Until they
        // arrive the column shows nothing rather than "Clear".
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: DashboardDataService.instance.allReportsStream,
          builder: (context, reports) {
            final summaries = reports.hasData
                ? summarizeModeration([
                    for (final doc in reports.data!.docs) doc.data(),
                  ])
                : null;
            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AdminTabbedTable<String>(
                    selected: _tab,
                    // Level with the tabs, at the right: ticking a box does
                    // not push the table down.
                    // Suspending is in the Admin menu (Suspend Accounts).
                    trailing: widget.buyersOnly
                        ? null
                        : AdminSelectionNote(
                            count: selected.length,
                            onClear: () => setState(_ticked.clear),
                          ),
                    onSelected: (tab) => setState(() {
                      _tab = tab;
                      _page = 0;
                      _ticked.clear();
                    }),
                    tabs: [
                      if (!widget.buyersOnly)
                        (
                          value: 'all',
                          label: 'All accounts',
                          count: count('all'),
                          icon: Icons.groups_2_outlined,
                        ),
                      (
                        value: 'buyers',
                        label: 'Buyers',
                        count: count('buyers'),
                        icon: Icons.shopping_basket_outlined,
                      ),
                      if (!widget.buyersOnly) ...[
                        (
                          value: 'approved',
                          label: 'Approved farmers',
                          count: count('approved'),
                          icon: Icons.verified_outlined,
                        ),
                        (
                          value: 'pending',
                          label: 'Pending review',
                          count: count('pending'),
                          icon: Icons.hourglass_empty_rounded,
                        ),
                        (
                          value: 'rejected',
                          label: 'Rejected',
                          count: count('rejected'),
                          icon: Icons.block_outlined,
                        ),
                      ],
                    ],
                    child: _table(
                      c,
                      filtered,
                      widget.buyersOnly ? count('buyers') == 0 : all.isEmpty,
                      summaries,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Shown while accounts are ticked: how many, a way to untick them, and
  // the actions that are safe to take on several accounts at once. There
  // is no bulk "confirm violation" (each needs its own review) and no
  // bulk delete.
  Widget _table(
    AdminPalette c,
    List<AdminAccountRow> rows,
    bool noAccounts,
    Map<String, ModerationSummary>? summaries,
  ) {
    final box = adminTableCard(c, tabbed: true);
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: box,
        child: AdminEmptyState(
          icon: Icons.groups_2_outlined,
          title: noAccounts
              ? (widget.buyersOnly ? 'No buyers yet' : 'No user accounts yet')
              : 'No accounts match these filters',
          subtitle: noAccounts
              ? widget.buyersOnly
                    ? 'Buyer accounts appear here once they register.'
                    : 'Buyer and farmer accounts appear here once they register.'
              : 'Try a different search or filter.',
        ),
      );
    }
    final pages = adminPageCount(rows.length);
    final page = _page.clamp(0, pages - 1);
    final visible = adminPageOf(rows, page);
    final secondary = TextStyle(color: c.textSecondary);
    final buyersOnly = widget.buyersOnly;
    return Container(
      width: double.infinity,
      decoration: adminTableCard(c, tabbed: true),
      // The header band follows the rounded corners.
      clipBehavior: Clip.antiAlias,
      padding: kAdminTablePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminTableFit(
            table: DataTable(
              headingRowColor: WidgetStateProperty.all(
                adminTableHeaderColor(c),
              ),
              dataRowColor: adminTableRowColor(c),
              columnSpacing: kAdminTableColumnSpacing,
              horizontalMargin: kAdminTableMargin,
              headingTextStyle: adminTableHeaderStyle(c),
              dataTextStyle: TextStyle(
                fontFamily: kAdminFontFamily,
                color: c.textPrimary,
                fontSize: 13,
              ),
              columns: [
                const DataColumn(label: Text('Name')),
                if (!buyersOnly) const DataColumn(label: Text('Role')),
                const DataColumn(label: Text('Email')),
                const DataColumn(label: Text('Area')),
                const DataColumn(label: Text('Registered')),
                const DataColumn(label: Text('Email Status')),
                if (!buyersOnly)
                  const DataColumn(label: Text('Farmer Application')),
                const DataColumn(label: Text('Moderation Status')),
                const DataColumn(label: Text('Account Status')),
                const DataColumn(label: Text('Actions')),
              ],
              rows: [
                for (final row in visible)
                  DataRow(
                    selected: _ticked.contains(row.uid),
                    // No tick boxes on the Buyers list.
                    onSelectChanged: buyersOnly
                        ? null
                        : (ticked) => setState(() {
                            if (ticked ?? false) {
                              _ticked.add(row.uid);
                            } else {
                              _ticked.remove(row.uid);
                            }
                          }),
                    cells: [
                      DataCell(
                        // The account's current photo, or its initials.
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AdminAvatar(
                              name: row.name,
                              photoUrl: row.photoUrl,
                              radius: 14,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              row.name.isEmpty ? '—' : row.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!buyersOnly)
                        DataCell(Text(row.isBuyer ? 'Buyer' : 'Farmer')),
                      DataCell(
                        Text(
                          row.email.isEmpty ? '—' : row.displayEmail,
                          style: secondary,
                        ),
                      ),
                      DataCell(
                        Text(
                          row.area.isEmpty ? 'Not saved' : row.area,
                          style: secondary,
                        ),
                      ),
                      DataCell(
                        Text(
                          row.registered == null
                              ? '—'
                              : DateFormat('MMM d, y').format(row.registered!),
                          style: secondary,
                        ),
                      ),
                      DataCell(
                        row.emailVerified
                            ? AdminStatusBadge(
                                text: 'Verified',
                                color: c.green,
                                bg: c.greenBg,
                              )
                            : AdminStatusBadge(
                                text: 'Not verified',
                                color: c.amber,
                                bg: c.amberBg,
                              ),
                      ),
                      if (!buyersOnly) DataCell(_identityBadge(c, row)),
                      DataCell(
                        summaries == null
                            ? Text('…', style: TextStyle(color: c.textMuted))
                            : adminModerationBadge(
                                c,
                                (summaries[row.uid] ?? ModerationSummary.none)
                                    .status,
                              ),
                      ),
                      DataCell(adminAccountStatusBadge(c, row.accountStatus)),
                      DataCell(
                        IconButton(
                          tooltip: 'View account',
                          icon: Icon(
                            Icons.visibility_outlined,
                            size: 18,
                            color: c.textSecondary,
                          ),
                          onPressed: () => showAdminAccountDialog(
                            context,
                            palette: c,
                            uid: row.uid,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          // 10 accounts a page.
          if (pages > 1)
            AdminTablePager(
              page: page,
              pageCount: pages,
              total: rows.length,
              onPage: (p) => setState(() => _page = p),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                'Showing ${rows.length} '
                '${rows.length == 1 ? 'account' : 'accounts'}',
                style: TextStyle(color: c.textSecondary, fontSize: 12.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _identityBadge(AdminPalette c, AdminAccountRow row) {
    final identity = row.identity;
    if (identity == null) {
      return Text('—', style: TextStyle(color: c.textMuted));
    }
    final (color, bg) = switch (identity) {
      AccountIdentity.verified => (c.green, c.greenBg),
      AccountIdentity.pendingReview => (c.amber, c.amberBg),
      AccountIdentity.rejected => (c.red, c.redBg),
    };
    return AdminStatusBadge(
      text: identityLabel(identity),
      color: color,
      bg: bg,
    );
  }
}
