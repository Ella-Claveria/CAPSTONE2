import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/dashboard_data_service.dart';
import '../services/moderation_model.dart';
import 'admin_dashboard_screen.dart';
import 'admin_filter_controls.dart';
import 'admin_user_accounts_view.dart';

/// Admin menu → Suspend Accounts: every buyer and farmer account with
/// where it stands and how many reports are against it — the most
/// reported first, flagged from [kSuspendReportThreshold] — and a Suspend
/// or Reactivate button on each. The suspension itself (its reason, how
/// long, the Audit Log entry) is [adminSetAccountsSuspended].
Future<void> showAdminSuspendAccounts(BuildContext context) {
  // A dialog sits outside the page's AdminThemeScope: hand the palette in.
  final palette =
      context.getInheritedWidgetOfExactType<AdminThemeScope>()?.palette ??
      AdminPalette.light;
  return showDialog<void>(
    context: context,
    builder: (_) => AdminThemeScope(
      palette: palette,
      child: _SuspendAccountsDialog(palette: palette),
    ),
  );
}

/// Reports against each account, by the reported account's uid. A report
/// the Admin dismissed does not count. Pure, so it can be tested.
Map<String, int> reportCountsByAccount(Iterable<Map<String, dynamic>> reports) {
  final counts = <String, int>{};
  for (final report in reports) {
    if (reportDecisionOf(report) == 'dismissed') continue;
    final uid = reportedUserIdOf(report);
    if (uid.isEmpty) continue;
    counts[uid] = (counts[uid] ?? 0) + 1;
  }
  return counts;
}

class _SuspendAccountsDialog extends StatefulWidget {
  final AdminPalette palette;
  const _SuspendAccountsDialog({required this.palette});

  @override
  State<_SuspendAccountsDialog> createState() => _SuspendAccountsDialogState();
}

class _SuspendAccountsDialogState extends State<_SuspendAccountsDialog> {
  String _search = '';
  // 'all', 'reported', 'active' or 'suspended'.
  String _show = 'all';
  // The account being suspended or reactivated right now.
  String? _workingOn;

  static bool _isSuspended(AdminAccountRow row) =>
      row.accountStatus == 'suspended' || row.accountStatus == 'deactivated';

  Future<void> _change(
    AdminAccountRow row,
    Map<String, int> reports, {
    required bool suspend,
  }) async {
    if (_workingOn != null) return;
    setState(() => _workingOn = row.uid);
    await adminSetAccountsSuspended(
      context,
      [row],
      suspend: suspend,
      reports: reports,
    );
    if (mounted) setState(() => _workingOn = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.palette;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
      title: Row(children: [const Expanded(child: Text('Suspend Accounts'))]),
      content: SizedBox(
        width: 660,
        height: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Accounts with $kSuspendReportThreshold or more reports are '
              'flagged and listed first. A suspended account cannot log in '
              'until the time you set has passed or it is reactivated; it is '
              'told why. Nothing is deleted.',
              style: TextStyle(fontSize: 12.5, color: c.textSecondary),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    style: TextStyle(color: c.textPrimary, fontSize: 13),
                    decoration: adminPillDecoration(
                      c,
                      hint: 'Search name, email or area…',
                      icon: Icons.search,
                    ),
                    onChanged: (value) => setState(() => _search = value),
                  ),
                ),
                const SizedBox(width: 10),
                AdminPillDropdown<String>(
                  value: _show,
                  width: 190,
                  icon: Icons.filter_list_rounded,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All accounts')),
                    DropdownMenuItem(
                      value: 'reported',
                      child: Text('$kSuspendReportThreshold+ reports'),
                    ),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(
                      value: 'suspended',
                      child: Text('Suspended'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _show = value),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: DashboardDataService.instance.allReportsStream,
                builder: (context, reportSnap) {
                  final reports = reportCountsByAccount([
                    for (final doc
                        in reportSnap.data?.docs ??
                            const <
                              QueryDocumentSnapshot<Map<String, dynamic>>
                            >[])
                      doc.data(),
                  ]);
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: DashboardDataService.instance.usersStream,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Center(
                          child: Text(
                            'Could not load the accounts. Check your '
                            'connection and try again.',
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        );
                      }
                      if (!snap.hasData) {
                        return const Center(child: AdminLoadingBar());
                      }
                      int count(AdminAccountRow r) => reports[r.uid] ?? 0;
                      final rows = [
                        for (final row in buildAccountRows([
                          for (final doc in snap.data!.docs)
                            (id: doc.id, data: doc.data()),
                        ]))
                          if (row.matches(_search) &&
                              switch (_show) {
                                'reported' =>
                                  count(row) >= kSuspendReportThreshold,
                                'active' => row.accountStatus == 'active',
                                'suspended' => _isSuspended(row),
                                _ => true,
                              })
                            row,
                      ];
                      // Most reported first, then newest first.
                      rows.sort((a, b) {
                        final byReports = count(b).compareTo(count(a));
                        if (byReports != 0) return byReports;
                        return (b.registered?.millisecondsSinceEpoch ?? 0)
                            .compareTo(
                              a.registered?.millisecondsSinceEpoch ?? 0,
                            );
                      });
                      if (rows.isEmpty) {
                        return Center(
                          child: Text(
                            _show == 'reported'
                                ? 'No account has $kSuspendReportThreshold '
                                      'or more reports.'
                                : 'No accounts match.',
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: c.border),
                        itemBuilder: (context, i) =>
                            _accountRow(c, rows[i], reports),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _accountRow(
    AdminPalette c,
    AdminAccountRow row,
    Map<String, int> reports,
  ) {
    final status = row.accountStatus;
    final (color, bg) = switch (status) {
      'active' => (c.green, c.greenBg),
      'banned' => (c.red, c.redBg),
      _ => (c.amber, c.amberBg),
    };
    final busy = _workingOn == row.uid;
    final role = row.isBuyer ? 'Buyer' : 'Farmer';
    final reportCount = reports[row.uid] ?? 0;
    final flagged = reportCount >= kSuspendReportThreshold;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          AdminAvatar(name: row.name, photoUrl: row.photoUrl, radius: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name.isEmpty ? 'Unnamed account' : row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  // A buyer's email is partly hidden, as in User Accounts.
                  [
                    role,
                    if (row.displayEmail.isNotEmpty) row.displayEmail,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                ),
                if (status == 'suspended') ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      suspensionUntilLabel(row.suspendedUntil),
                      if (row.suspensionReason.isNotEmpty) row.suspensionReason,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.amber, fontSize: 11.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          // How many reports are against it; red from the threshold.
          Tooltip(
            message: flagged
                ? '$reportCount reports — review for suspension'
                : '$reportCount ${reportCount == 1 ? 'report' : 'reports'}',
            child: Container(
              constraints: const BoxConstraints(minWidth: 64),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: flagged ? c.redBg : c.surfaceAlt,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.flag_outlined,
                    size: 13,
                    color: flagged ? c.red : c.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$reportCount',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: flagged ? c.red : c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          AdminStatusBadge(
            text: accountStatusLabel(status),
            color: color,
            bg: bg,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 116,
            child: status == 'active'
                ? OutlinedButton(
                    onPressed: _workingOn != null
                        ? null
                        : () => _change(row, reports, suspend: true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.red,
                      side: BorderSide(color: c.red.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(busy ? 'Suspending…' : 'Suspend'),
                  )
                : _isSuspended(row)
                ? FilledButton(
                    onPressed: _workingOn != null
                        ? null
                        : () => _change(row, reports, suspend: false),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(busy ? 'Working…' : 'Reactivate'),
                  )
                // A ban is decided on a report and is not undone here.
                : Center(
                    child: Text(
                      '—',
                      style: TextStyle(color: c.textMuted, fontSize: 13),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
