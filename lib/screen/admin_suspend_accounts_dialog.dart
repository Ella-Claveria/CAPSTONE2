import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/dashboard_data_service.dart';
import '../services/moderation_model.dart';
import 'admin_dashboard_screen.dart';
import 'admin_filter_controls.dart';
import 'admin_user_accounts_view.dart';

/// Admin menu → Suspend Accounts: every buyer and farmer account with
/// where it stands, and a Suspend or Reactivate button on each. The
/// suspension itself (its reason, the Audit Log entry) is
/// [adminSetAccountsSuspended].
Future<void> showAdminSuspendAccounts(BuildContext context) {
  // A dialog sits outside the page's AdminThemeScope: hand the palette in.
  final palette = AdminThemeScope.of(context).palette;
  return showDialog<void>(
    context: context,
    builder: (_) => _SuspendAccountsDialog(palette: palette),
  );
}

class _SuspendAccountsDialog extends StatefulWidget {
  final AdminPalette palette;
  const _SuspendAccountsDialog({required this.palette});

  @override
  State<_SuspendAccountsDialog> createState() => _SuspendAccountsDialogState();
}

class _SuspendAccountsDialogState extends State<_SuspendAccountsDialog> {
  String _search = '';
  // 'all', 'active' or 'suspended'.
  String _show = 'all';
  // The account being suspended or reactivated right now.
  String? _workingOn;

  static bool _isSuspended(AdminAccountRow row) =>
      row.accountStatus == 'suspended' || row.accountStatus == 'deactivated';

  Future<void> _change(AdminAccountRow row, {required bool suspend}) async {
    if (_workingOn != null) return;
    setState(() => _workingOn = row.uid);
    await adminSetAccountsSuspended(context, [row], suspend: suspend);
    if (mounted) setState(() => _workingOn = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.palette;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
      title: Row(
        children: [
          const Expanded(child: Text('Suspend Accounts')),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, size: 20, color: c.textSecondary),
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'A suspended account cannot log in until it is reactivated. '
              'Nothing is deleted: its orders, listings, reports and '
              'reviews are kept.',
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
                  width: 170,
                  icon: Icons.filter_list_rounded,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All accounts')),
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
                stream: DashboardDataService.instance.usersStream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Text(
                        'Could not load the accounts. Check your connection '
                        'and try again.',
                        style: TextStyle(color: c.textSecondary, fontSize: 13),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(child: AdminLoadingBar());
                  }
                  final rows = [
                    for (final row in buildAccountRows([
                      for (final doc in snap.data!.docs)
                        (id: doc.id, data: doc.data()),
                    ]))
                      if (row.matches(_search) &&
                          (_show == 'all' ||
                              (_show == 'active' &&
                                  row.accountStatus == 'active') ||
                              (_show == 'suspended' && _isSuspended(row))))
                        row,
                  ];
                  if (rows.isEmpty) {
                    return Center(
                      child: Text(
                        'No accounts match.',
                        style: TextStyle(color: c.textSecondary, fontSize: 13),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: c.border),
                    itemBuilder: (context, i) => _accountRow(c, rows[i]),
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

  Widget _accountRow(AdminPalette c, AdminAccountRow row) {
    final status = row.accountStatus;
    final (color, bg) = switch (status) {
      'active' => (c.green, c.greenBg),
      'banned' => (c.red, c.redBg),
      _ => (c.amber, c.amberBg),
    };
    final busy = _workingOn == row.uid;
    final role = row.isBuyer ? 'Buyer' : 'Farmer';

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
              ],
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
                        : () => _change(row, suspend: true),
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
                        : () => _change(row, suspend: false),
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
