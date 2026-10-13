import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/audit_log_service.dart';
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

/// Suspends the accounts given that are active (asking for the reason
/// first), or reactivates the ones that are suspended or deactivated.
/// True when it was done.
// A ban is decided on a report,
// one account at a time, and is not undone from here. Nothing is ever
// deleted: orders, reports and reviews keep pointing at a real account.
Future<bool> adminSetAccountsSuspended(
  BuildContext context,
  List<AdminAccountRow> selected, {
  required bool suspend,
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
  final reasonController = TextEditingController();
  var missingReason = false;
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(suspend ? 'Suspend $label?' : 'Reactivate $label?'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                suspend
                    ? 'A suspended account cannot log in until an Admin '
                          'reactivates it. Its orders, listings, reports '
                          'and reviews are kept.'
                    : 'The account will be able to log in again.',
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
                const SizedBox(height: 14),
                AdminField(
                  controller: reasonController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: adminMultilineDecoration(
                    dialogContext,
                    labelText: 'Reason (required)',
                  ),
                ),
                if (missingReason)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      'Give the reason for the suspension.',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (suspend && reasonController.text.trim().isEmpty) {
                setDialogState(() => missingReason = true);
                return;
              }
              Navigator.of(dialogContext).pop(true);
            },
            child: Text(suspend ? 'Suspend' : 'Reactivate'),
          ),
        ],
      ),
    ),
  );
  final reason = reasonController.text.trim();
  if (confirmed != true || !context.mounted) return false;
  if (!await ConnectivityService.instance.checkNow()) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(kNoInternetActionMessage)));
    }
    return false;
  }

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
      '${targets.map((r) => r.name.isEmpty ? r.uid : r.name).join(', ')}.'
      '${suspend ? ' Reason: $reason' : ''}',
    );
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${suspend ? 'Suspended' : 'Reactivated'} $label.'),
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
  const AdminUserAccountsView({super.key});

  @override
  State<AdminUserAccountsView> createState() => _AdminUserAccountsViewState();
}

class _AdminUserAccountsViewState extends State<AdminUserAccountsView>
    with AdminPageSearch {
  // Typed in the header's search box.
  String get _search => pageSearch;

  @override
  void onPageSearchChanged() => _shown = _pageSize;

  // The open tab: every account, the buyers, or the farmers whose
  // application is approved, pending or rejected.
  String _tab = 'all';

  // Rows whose box is ticked, by account id.
  final Set<String> _ticked = {};

  static bool _inTab(AdminAccountRow row, String tab) => switch (tab) {
    'buyers' => row.isBuyer,
    'approved' => row.identity == AccountIdentity.verified,
    'pending' => row.identity == AccountIdentity.pendingReview,
    'rejected' => row.identity == AccountIdentity.rejected,
    _ => true,
  };

  static const int _pageSize = 50;
  int _shown = _pageSize;

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
                    trailing: AdminSelectionNote(
                      count: selected.length,
                      onClear: () => setState(_ticked.clear),
                    ),
                    onSelected: (tab) => setState(() {
                      _tab = tab;
                      _shown = _pageSize;
                      _ticked.clear();
                    }),
                    tabs: [
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
                    child: _table(c, filtered, all.isEmpty, summaries),
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
              ? 'No user accounts yet'
              : 'No accounts match these filters',
          subtitle: noAccounts
              ? 'Buyer and farmer accounts appear here once they register.'
              : 'Try a different search or filter.',
        ),
      );
    }
    final visible = rows.take(_shown).toList();
    final secondary = TextStyle(color: c.textSecondary);
    return Container(
      width: double.infinity,
      decoration: adminTableCard(c, tabbed: true),
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
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Role')),
                DataColumn(label: Text('Email')),
                DataColumn(label: Text('Area')),
                DataColumn(label: Text('Registered')),
                DataColumn(label: Text('Email Status')),
                DataColumn(label: Text('Farmer Application')),
                DataColumn(label: Text('Moderation Status')),
                DataColumn(label: Text('Account Status')),
                DataColumn(label: Text('Actions')),
              ],
              rows: [
                for (final row in visible)
                  DataRow(
                    selected: _ticked.contains(row.uid),
                    onSelectChanged: (ticked) => setState(() {
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
                      DataCell(_identityBadge(c, row)),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Showing ${visible.length} of ${rows.length} '
                    '${rows.length == 1 ? 'account' : 'accounts'}',
                    style: TextStyle(color: c.textSecondary, fontSize: 12),
                  ),
                ),
                if (rows.length > visible.length)
                  TextButton(
                    onPressed: () => setState(() => _shown += _pageSize),
                    child: const Text('Show more'),
                  ),
              ],
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
