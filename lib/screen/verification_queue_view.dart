import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:convert'; // Decodes Base64-embedded verification document images

import '../services/rsba_number.dart';
import 'admin_filter_controls.dart';
import '../services/audit_log_service.dart';
import '../services/connectivity_service.dart';
import '../services/dashboard_data_service.dart';
import 'admin_dashboard_screen.dart'
    show AdminEmptyState, AdminPalette, AdminStatusBadge, AdminThemeScope;
import 'admin_overview_widgets.dart';

/// Which applications the page lists, chosen with its summary cards.
enum _QueueFilter { pending, approved, rejected }

/// Farmer Applications. Its job is the queue of applications still awaiting
/// an admin decision — role == 'farmer' && approvalStatus == 'pending'.
/// Above it, the same cards as the Dashboard's Overview: how many
/// applications are pending, approved and rejected. Clicking one lists
/// those applications. Approved Farmers have
/// their own dedicated page/nav item, see farmer_list_view.dart (a fully
/// separate screen — it does not share this file's dialog or data loaders).
class VerificationQueueView extends StatefulWidget {
  const VerificationQueueView({super.key});

  @override
  State<VerificationQueueView> createState() => _VerificationQueueViewState();
}

class _VerificationQueueViewState extends State<VerificationQueueView> {
  _QueueFilter _filter = _QueueFilter.pending;

  // The Dashboard's Overview cards. Each lists its applications below;
  // clicking the chosen one again goes back to the pending queue.
  Widget _summary({
    required int pending,
    required int approved,
    required int rejected,
  }) {
    AdminOverviewItem card(
      _QueueFilter filter, {
      required String label,
      required IconData icon,
      required int count,
      required String caption,
      bool attention = false,
    }) => AdminOverviewItem(
      label: label,
      icon: icon,
      value: '$count',
      caption: caption,
      attention: attention,
      selected: _filter == filter,
      onTap: () => setState(
        () => _filter = _filter == filter ? _QueueFilter.pending : filter,
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: AdminOverviewStrip(
        items: [
          card(
            _QueueFilter.pending,
            label: 'Pending Verifications',
            icon: Icons.fact_check_outlined,
            count: pending,
            caption: 'Farmers awaiting admin review',
            attention: true,
          ),
          card(
            _QueueFilter.approved,
            label: 'Approved Farmers',
            icon: Icons.verified_outlined,
            count: approved,
            caption: 'Applications approved',
          ),
          card(
            _QueueFilter.rejected,
            label: 'Rejected Applications',
            icon: Icons.block_outlined,
            count: rejected,
            caption: 'Applications not approved',
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(AdminPalette c, String title, int? count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        count == null ? title : '$title ($count)',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: c.textPrimary,
        ),
      ),
    );
  }

  /// One decided application: who, the decision and when, and the reason
  /// for a rejection. The eye opens the same record as the pending list.
  Widget _reviewedRow(
    BuildContext context,
    AdminPalette c,
    String uid,
    Map<String, dynamic> profile,
    Map<String, dynamic>? verif,
    DateTime? decided, {
    required bool last,
  }) {
    final name =
        _firstNonEmpty([
          verif?['fullName'],
          profile['fullName'],
          profile['name'],
        ]) ??
        'Unknown Farmer';
    final approved = profile['approvalStatus'] == 'approved';
    final barangay = _firstNonEmpty([profile['barangay']]);
    final reason = _firstNonEmpty([verif?['rejectionReason']]);
    final details = [
      'RSBA No.: ${farmerIdOf(profile, verif) ?? kNoFarmerId}',
      ?barangay,
      if (decided != null) DateFormat('MMM d, y').format(decided),
    ].join('  •  ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          AdminAvatar(
            name: name,
            photoUrl: profile['photoUrl']?.toString(),
            radius: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  details,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                ),
                if (!approved && reason != null)
                  Text(
                    'Reason: $reason',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AdminStatusBadge(
            text: approved ? 'Approved' : 'Rejected',
            color: approved ? c.green : c.red,
            bg: approved ? c.greenBg : c.redBg,
          ),
          IconButton(
            tooltip: 'View full verification details',
            icon: Icon(Icons.visibility_outlined, color: c.iconInactive),
            onPressed: () => showFarmerVerificationDetails(context, uid: uid),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The title is in the utility bar above.
          Expanded(
            // Sourced from DashboardDataService's shared `users` stream (see
            // its class doc) instead of a separate getPendingFarmers()
            // listener — role == 'farmer' && approvalStatus == 'pending' (or
            // missing — the same "missing defaults to pending" convention
            // used everywhere else in the app) filtered client-side from the
            // already-shared full collection. verificationDocs is read the
            // same way — one shared stream, looked up per row — instead of
            // this screen previously opening a brand-new live listener on
            // verificationDocs/{uid} for every single pending farmer, torn
            // down and resubscribed en masse on every unrelated update.
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: DashboardDataService.instance.usersStream,
              builder: (context, usersSnap) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: DashboardDataService.instance.verificationDocsStream,
                  builder: (context, verifSnap) {
                    if (usersSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: AdminLoadingBar());
                    }

                    if (usersSnap.hasError) {
                      return Center(
                        child: Text(
                          'Error loading queue.',
                          style: TextStyle(color: c.textSecondary),
                        ),
                      );
                    }

                    final docs = (usersSnap.data?.docs ?? []).where((d) {
                      final data = d.data();
                      if (data['role'] != 'farmer') return false;
                      final status = data['approvalStatus'];
                      return status == null || status == 'pending';
                    }).toList();

                    final verifByUid = <String, Map<String, dynamic>>{
                      for (final d in verifSnap.data?.docs ?? const [])
                        d.id: d.data(),
                    };
                    // Every farmer account by Farmer ID, to point out a
                    // number that is already on another account.
                    final namesByFarmerId = <String, Map<String, String>>{};
                    for (final d in usersSnap.data?.docs ?? const []) {
                      final data = d.data();
                      if (data['role'] != 'farmer') continue;
                      final id = farmerIdOf(data, verifByUid[d.id]);
                      if (id == null) continue;
                      (namesByFarmerId[id] ??= {})[d.id] =
                          _firstNonEmpty([data['fullName'], data['name']]) ??
                          'Unknown Farmer';
                    }

                    // Decided applications, newest decision first: the page
                    // still has something to show when nothing is waiting.
                    var approvedCount = 0;
                    var rejectedCount = 0;
                    final reviewed =
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    for (final d in usersSnap.data?.docs ?? const []) {
                      final data = d.data();
                      if (data['role'] != 'farmer') continue;
                      final status = data['approvalStatus'];
                      if (status == 'approved') approvedCount++;
                      if (status == 'rejected') rejectedCount++;
                      if (status == 'approved' || status == 'rejected') {
                        reviewed.add(d);
                      }
                    }
                    DateTime? decidedAt(Map<String, dynamic> data) =>
                        ((data['reviewedAt'] ?? data['verifiedAt'])
                                as Timestamp?)
                            ?.toDate();
                    reviewed.sort((a, b) {
                      final ta = decidedAt(a.data());
                      final tb = decidedAt(b.data());
                      if (ta == null && tb == null) return 0;
                      if (ta == null) return 1;
                      if (tb == null) return -1;
                      return tb.compareTo(ta);
                    });
                    final summary = _summary(
                      pending: docs.length,
                      approved: approvedCount,
                      rejected: rejectedCount,
                    );

                    // Approved or Rejected card chosen: every application
                    // with that decision, newest first.
                    if (_filter != _QueueFilter.pending) {
                      final approved = _filter == _QueueFilter.approved;
                      final decided = [
                        for (final d in reviewed)
                          if ((d.data()['approvalStatus'] == 'approved') ==
                              approved)
                            d,
                      ];
                      return ListView(
                        children: [
                          summary,
                          _sectionTitle(
                            c,
                            approved
                                ? 'Approved applications'
                                : 'Rejected applications',
                            decided.length,
                          ),
                          if (decided.isEmpty)
                            AdminEmptyState(
                              icon: approved
                                  ? Icons.verified_outlined
                                  : Icons.block_outlined,
                              title: approved
                                  ? 'No approved applications yet'
                                  : 'No rejected applications',
                              subtitle: approved
                                  ? 'Farmers you approve will be listed here.'
                                  : 'Applications you reject will be listed '
                                        'here, with the reason.',
                            )
                          else
                            Card(
                              margin: EdgeInsets.zero,
                              child: Column(
                                children: [
                                  for (final d in decided)
                                    _reviewedRow(
                                      context,
                                      c,
                                      d.id,
                                      d.data(),
                                      verifByUid[d.id],
                                      decidedAt(d.data()),
                                      last: d == decided.last,
                                    ),
                                ],
                              ),
                            ),
                        ],
                      );
                    }

                    return ListView(
                      children: [
                        summary,
                        _sectionTitle(c, 'Pending applications', docs.length),
                        if (docs.isEmpty)
                          const AdminEmptyState(
                            icon: Icons.task_alt_rounded,
                            title: 'All caught up',
                            subtitle:
                                'No farmer applications are waiting for review. '
                                'New ones will appear here as soon as a farmer '
                                'registers.',
                          )
                        else
                          for (final d in docs)
                            FarmerApplicationCard(
                              uid: d.id,
                              profile: d.data(),
                              verif: verifByUid[d.id],
                              sameFarmerId: [
                                for (final other
                                    in (namesByFarmerId[farmerIdOf(
                                              d.data(),
                                              verifByUid[d.id],
                                            )] ??
                                            const {})
                                        .entries)
                                  if (other.key != d.id) other.value,
                              ],
                            ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One application waiting for a decision, as a review card: who applied
/// (photo or initials, name, "Pending Review"), the details to check —
/// RSBA No., email, barangay and when it was submitted — anything that
/// needs a second look, and View Details / Reject / Approve.
class FarmerApplicationCard extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> profile;
  final Map<String, dynamic>? verif;

  /// Other farmer accounts with the same RSBA No.
  final List<String> sameFarmerId;

  const FarmerApplicationCard({
    super.key,
    required this.uid,
    required this.profile,
    required this.verif,
    this.sameFarmerId = const [],
  });

  @override
  Widget build(BuildContext context) {
    // verif (from DashboardDataService's shared verificationDocsStream, see
    // caller) is supplementary only — submission date and the document
    // image live on verificationDocs, but the row (and the Approve/Reject
    // actions below) must never depend on this document existing.
    final fullName =
        _firstNonEmpty([
          verif?['fullName'],
          profile['fullName'],
          profile['name'],
        ]) ??
        'Unknown Farmer';
    final email = (profile['email'] ?? '—').toString();
    final rawBarangay = profile['barangay']?.toString().trim();
    final barangay = (rawBarangay == null || rawBarangay.isEmpty)
        ? '—'
        : rawBarangay;
    final submittedAt = verif?['submittedAt'] as Timestamp?;
    final dateSubmitted = submittedAt != null
        ? DateFormat('MMM d, y').format(submittedAt.toDate())
        : '—';
    final document = (verif?['document'] ?? '').toString();
    // The Farmer ID is the RSBA number typed at registration. It is what
    // the Admin checks against the registry before approving — the app
    // itself does not verify it.
    final farmerId = farmerIdOf(profile, verif);
    // Nothing to check an application against: no number and no document.
    final nothingToCheck = farmerId == null && document.isEmpty;

    final c = AdminThemeScope.of(context).palette;
    final warnings = [
      if (sameFarmerId.isNotEmpty)
        'This RSBA No. is also on another farmer account: '
            '${sameFarmerId.join(', ')}.',
      if (nothingToCheck)
        'No RSBA No. was submitted, so there is nothing to check this '
            'application against.',
    ];

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.visibility_outlined, size: 18),
          label: const Text('View Details'),
          style: _actionStyle(c.textPrimary, c.border),
          onPressed: () => showFarmerVerificationDetails(context, uid: uid),
        ),
        // Only an older application has a document; the RSBA number took
        // its place on the registration form.
        if (document.isNotEmpty)
          OutlinedButton.icon(
            icon: const Icon(Icons.image_search, size: 18),
            label: const Text('View Doc'),
            style: _actionStyle(c.textPrimary, c.border),
            onPressed: () => _showDocumentDialog(context, document),
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.close_rounded, size: 18),
          label: const Text('Reject'),
          style: _actionStyle(c.red, c.red.withValues(alpha: 0.45)),
          onPressed: () => rejectFarmerAccount(context, uid, fullName),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Approve'),
          style: FilledButton.styleFrom(
            // The portal's dark green, as on every main action.
            backgroundColor: adminActionColor(c),
            foregroundColor: Colors.white,
            disabledBackgroundColor: c.border,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          onPressed: nothingToCheck
              ? null
              : () => approveFarmerAccount(context, uid, fullName),
        ),
      ],
    );

    // Who applied: photo or initials, the name and where it stands.
    final header = Row(
      children: [
        AdminAvatar(
          name: fullName,
          photoUrl: profile['photoUrl']?.toString(),
          radius: 22,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    fullName,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  AdminStatusBadge(
                    text: 'Pending Review',
                    color: c.amber,
                    bg: c.amberBg,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Farmer application',
                style: TextStyle(fontSize: 12.5, color: c.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );

    // The application's details, each with its label.
    final details = Wrap(
      spacing: 28,
      runSpacing: 12,
      children: [
        _ApplicationField(
          icon: Icons.badge_outlined,
          label: 'RSBA No.',
          value: farmerId ?? kNoFarmerId,
          emphasis: true,
          valueColor: farmerId == null ? c.red : null,
        ),
        _ApplicationField(
          icon: Icons.mail_outline_rounded,
          label: 'Email',
          value: email,
        ),
        _ApplicationField(
          icon: Icons.location_on_outlined,
          label: 'Barangay',
          value: barangay,
        ),
        _ApplicationField(
          icon: Icons.event_outlined,
          label: 'Submitted',
          value: dateSubmitted,
        ),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0E3210),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          // Wide: the actions beside the header; narrow: under the details.
          final wide = box.maxWidth >= 860;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  Row(
                    children: [
                      Expanded(child: header),
                      const SizedBox(width: 16),
                      actions,
                    ],
                  )
                else
                  header,
                const SizedBox(height: 14),
                Divider(height: 1, color: c.border),
                const SizedBox(height: 14),
                // Lined up under the name, past the photo.
                Padding(
                  padding: const EdgeInsets.only(left: 58),
                  child: details,
                ),
                for (final warning in warnings) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(left: 58),
                    child: _ApplicationWarning(text: warning),
                  ),
                ],
                if (!wide) ...[
                  const SizedBox(height: 16),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  ButtonStyle _actionStyle(Color color, Color border) =>
      OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: border),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      );
}

/// One labelled detail of an application: a small grey label with its
/// icon, and the value under it.
class _ApplicationField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool emphasis;
  final Color? valueColor;

  const _ApplicationField({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasis = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: c.textMuted),
              const SizedBox(width: 5),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: c.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: emphasis ? 14 : 13.5,
              fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: emphasis ? 0.4 : null,
              color: valueColor ?? c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Something the Admin should look at before deciding, in a soft red
/// notice.
class _ApplicationWarning extends StatelessWidget {
  final String text;
  const _ApplicationWarning({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: c.redBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.red.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 17, color: c.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: c.red, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

String? _firstNonEmpty(List<dynamic> candidates) {
  for (final c in candidates) {
    final s = c?.toString().trim();
    if (s != null && s.isNotEmpty) return s;
  }
  return null;
}

void _showDocumentDialog(BuildContext context, String document) {
  Widget imageWidget;

  try {
    if (document.startsWith('http://') || document.startsWith('https://')) {
      imageWidget = Image.network(
        document,
        width: 400,
        height: 400,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Text('Failed to load document image.'),
      );
    } else if (document.isNotEmpty) {
      // Clean up the string in case it has metadata like "data:image/jpeg;base64,"
      final cleanBase64 = document.contains(',')
          ? document.split(',').last
          : document;

      imageWidget = Image.memory(
        base64Decode(cleanBase64),
        width: 400,
        height: 400,
        fit: BoxFit.contain,
      );
    } else {
      imageWidget = const Text('No document image provided.');
    }
  } catch (e) {
    imageWidget = const Text('Failed to load image format.');
  }

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Agricultural Certification'),
      content: imageWidget,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// A confirmation dialog that runs [action] only once the admin confirms,
/// showing an inline spinner and disabling both buttons for the duration —
/// shared by approve and reject so neither can be double-submitted or
/// triggered by an accidental click.
Future<void> _confirmAndRun(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required Color confirmColor,
  bool withReason = false,
  required Future<void> Function(String? reason) action,
}) async {
  final reasonController = withReason ? TextEditingController() : null;
  bool loading = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => PopScope(
        canPop: !loading,
        child: AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (withReason) ...[
                const SizedBox(height: 14),
                AdminField(
                  controller: reasonController!,
                  maxLines: 2,
                  enabled: !loading,
                  decoration: adminMultilineDecoration(
                    dialogContext,
                    hintText: 'Reason for rejection (optional)',
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: confirmColor,
                foregroundColor: Colors.white,
              ),
              onPressed: loading
                  ? null
                  : () async {
                      setDialogState(() => loading = true);
                      await action(reasonController?.text.trim());
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
              child: loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(confirmLabel),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Approve a farmer application. `uid` is the farmer's own Firebase Auth
/// uid — the same id as their `users/{uid}` document.
Future<void> approveFarmerAccount(
  BuildContext context,
  String uid,
  String farmerName,
) {
  return _confirmAndRun(
    context,
    title: 'Approve this Farmer account?',
    message:
        'This farmer will be verified and able to list products and sell on AgriTrade+.',
    confirmLabel: 'Approve',
    confirmColor: adminActionOf(context),
    action: (_) => _setFarmerApproval(
      context,
      uid,
      approved: true,
      farmerName: farmerName,
    ),
  );
}

Future<void> rejectFarmerAccount(
  BuildContext context,
  String uid,
  String farmerName,
) {
  return _confirmAndRun(
    context,
    title: 'Reject this Farmer verification?',
    message:
        'The farmer will be notified that their application was not approved.',
    confirmLabel: 'Reject',
    confirmColor: Colors.red,
    withReason: true,
    action: (reason) => _setFarmerApproval(
      context,
      uid,
      approved: false,
      reason: reason,
      farmerName: farmerName,
    ),
  );
}

/// The one place approve/reject actually writes to Firestore. `users/{uid}`
/// is the canonical record the rest of the app (login routing, the pending
/// count, security rules) reads — it is always written. `verificationDocs`
/// is kept in sync too (created if it never existed) purely as the
/// submission/audit trail; it is never the source of truth for access.
Future<void> _setFarmerApproval(
  BuildContext context,
  String uid, {
  required bool approved,
  required String farmerName,
  String? reason,
}) async {
  if (!await ConnectivityService.instance.checkNow()) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(kNoInternetActionMessage)));
    }
    return;
  }

  final adminUid = FirebaseAuth.instance.currentUser?.uid;

  // A Farmer must never be able to approve their own account. Firestore
  // rules already make this practically unreachable (only an account with
  // role == 'admin' can write approvalStatus at all, and a single account
  // can't be both an admin and the farmer record it's acting on) — this is
  // an explicit, defense-in-depth guard at the call site itself rather
  // than relying on that alone.
  if (adminUid != null && adminUid == uid) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot approve or reject your own account.'),
        ),
      );
    }
    return;
  }

  final status = approved ? 'approved' : 'rejected';

  try {
    final userUpdate = <String, dynamic>{
      'approvalStatus': status,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': adminUid,
      // approvalStatus is the single source of truth for verification
      // state — isVerified is a documented, intentionally-maintained
      // mirror of it (see docs/firestore-schema-migration.md), and must
      // never independently drift (a reject used to leave a farmer's
      // previous isVerified untouched). Written symmetrically here so it
      // stays accurate even though nothing currently reads it directly for
      // access/ranking decisions (those now read approvalStatus itself —
      // see buyer_explore_screen.dart / buyer_search_screen.dart).
      'isVerified': approved,
    };
    if (approved) userUpdate['verifiedAt'] = FieldValue.serverTimestamp();
    final batch = FirebaseFirestore.instance.batch();
    batch.update(
      FirebaseFirestore.instance.collection('users').doc(uid),
      userUpdate,
    );

    final docUpdate = <String, dynamic>{
      'status': status,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': adminUid,
    };
    if (!approved && reason != null && reason.isNotEmpty) {
      docUpdate['rejectionReason'] = reason;
    }
    if (approved) docUpdate['rejectionReason'] = FieldValue.delete();
    batch.set(
      FirebaseFirestore.instance.collection('verificationDocs').doc(uid),
      docUpdate,
      SetOptions(merge: true),
    );
    await batch.commit();

    AuditLogService.log(
      approved ? AuditAction.approveFarmer : AuditAction.rejectFarmer,
      approved
          ? 'Approved farmer $farmerName.'
          : 'Rejected farmer $farmerName.${reason != null && reason.isNotEmpty ? ' Reason: $reason' : ''}',
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          approved ? 'Farmer approved successfully!' : 'Application rejected.',
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Error updating farmer: $e')));
  }
}

/// Opens the full verification/profile detail dialog for one farmer — used
/// by the Verification Queue's pending list and the Home dashboard's
/// "Recent Verification Requests" table, so both stay backed by the same
/// live data and the same approve/reject actions. The Farmer List page has
/// its own, separate detail dialog and does not use this one.
Future<void> showFarmerVerificationDetails(
  BuildContext context, {
  required String uid,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _FarmerVerificationDetailDialog(uid: uid),
  );
}

class _FarmerVerificationDetailDialog extends StatefulWidget {
  final String uid;
  const _FarmerVerificationDetailDialog({required this.uid});

  @override
  State<_FarmerVerificationDetailDialog> createState() =>
      _FarmerVerificationDetailDialogState();
}

class _FarmerVerificationDetailDialogState
    extends State<_FarmerVerificationDetailDialog>
    with AdminReadOnce {
  String get uid => widget.uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: watchOnce(
        'user',
        () =>
            FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      ),
      builder: (context, userSnap) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: watchOnce(
            'verification',
            () => FirebaseFirestore.instance
                .collection('verificationDocs')
                .doc(uid)
                .snapshots(),
          ),
          builder: (context, verifSnap) {
            if (userSnap.hasError || verifSnap.hasError) {
              return AlertDialog(
                title: const Text('Something went wrong'),
                content: const Text(
                  'Could not load this farmer\'s details. Please try again.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              );
            }
            if (!userSnap.hasData || !verifSnap.hasData) {
              return const AlertDialog(
                content: SizedBox(
                  height: 120,
                  child: Center(child: AdminLoadingBar()),
                ),
              );
            }

            final user = userSnap.data!.data();
            if (user == null) {
              return AlertDialog(
                title: const Text('Account Not Found'),
                content: const Text(
                  'This farmer\'s account could not be found. It may have been removed.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              );
            }
            final verif = verifSnap.data!.data();

            final fullName =
                _firstNonEmpty([
                  verif?['fullName'],
                  user['fullName'],
                  user['name'],
                ]) ??
                'Unknown Farmer';
            final email = (user['email'] ?? '—').toString();
            final barangay = _firstNonEmpty([user['barangay']]) ?? '—';
            final municipality = _firstNonEmpty([user['municipality']]);
            // The number given at registration, read live from the account: a
            // change the farmer makes in the app shows here by itself.
            final phone =
                _firstNonEmpty([
                  user['mobileNumber'],
                  user['phoneNumber'],
                  user['phone'],
                ]) ??
                '—';
            final approvalStatus = (user['approvalStatus'] ?? 'pending')
                .toString();
            final statusLabel = approvalStatus.isEmpty
                ? 'Pending'
                : '${approvalStatus[0].toUpperCase()}${approvalStatus.substring(1)}';
            final submittedAt = verif?['submittedAt'] as Timestamp?;
            final dateSubmitted = submittedAt != null
                ? DateFormat('MMM d, y – h:mm a').format(submittedAt.toDate())
                : '—';
            final reviewedAt = user['reviewedAt'] as Timestamp?;
            final dateReviewed = reviewedAt != null
                ? DateFormat('MMM d, y – h:mm a').format(reviewedAt.toDate())
                : '—';
            final reviewedByUid = _firstNonEmpty([user['reviewedBy']]);
            // Verified by the app's own email code, a verified email link,
            // or a Google sign-in (the same reading as User Accounts).
            final emailVerified =
                user['emailOtpVerified'] == true ||
                user['emailVerified'] == true ||
                (user['authProvider'] ?? '').toString() == 'google';
            final province = _firstNonEmpty([user['province']]);
            final rejectionReason = (verif?['rejectionReason'] ?? '')
                .toString();

            return AlertDialog(
              title: const Text('Farmer Application and Verification Record'),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The farmer's CURRENT profile photo, read live from
                      // their own account record (the one the mobile app
                      // updates) — nothing is copied onto the application.
                      // A new farmer usually has none yet: their initials
                      // are shown instead, and it is not needed to approve.
                      Row(
                        children: [
                          AdminAvatar(
                            name: fullName,
                            photoUrl: user['photoUrl']?.toString(),
                            radius: 28,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              fullName,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _sectionLabel('Farmer Information'),
                      _detailRow('Full Name', fullName),
                      _detailRow(
                        'RSBA No.',
                        farmerIdOf(user, verif) ?? kNoFarmerId,
                      ),
                      _detailRow('Email', email),
                      _detailRow('Phone Number', phone),
                      _detailRow('Barangay', barangay),
                      _detailRow(
                        'Municipality / City',
                        [municipality, province].whereType<String>().isEmpty
                            ? '—'
                            : [
                                municipality,
                                province,
                              ].whereType<String>().join(', '),
                      ),
                      const SizedBox(height: 10),
                      _sectionLabel('Application Details'),
                      _detailRow(
                        'Email Verification Status',
                        emailVerified ? 'Verified' : 'Not verified',
                      ),
                      _detailRow('Application Status', statusLabel),
                      _detailRow('Date Submitted', dateSubmitted),
                      _detailRow('Reviewed At', dateReviewed),
                      // The officer's name, not their account code.
                      FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        future: reviewedByUid == null
                            ? null
                            : readOnce(
                                'officer/$reviewedByUid',
                                () => FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(reviewedByUid)
                                    .get(),
                              ),
                        builder: (context, officerSnap) {
                          final officer = officerSnap.data?.data();
                          return _detailRow(
                            'Reviewed By',
                            reviewedByUid == null
                                ? '—'
                                : _firstNonEmpty([
                                        officer?['fullName'],
                                        officer?['name'],
                                        officer?['email'],
                                      ]) ??
                                      (officerSnap.connectionState ==
                                              ConnectionState.done
                                          ? 'Administrator'
                                          : '…'),
                          );
                        },
                      ),
                      if (approvalStatus == 'rejected' &&
                          rejectionReason.isNotEmpty)
                        _detailRow('Rejection Reason', rejectionReason),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
                if (approvalStatus == 'pending') ...[
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      rejectFarmerAccount(context, uid, fullName);
                    },
                    child: const Text('Reject'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      approveFarmerAccount(context, uid, fullName);
                    },
                    child: const Text('Approve'),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12.5,
          color: Colors.grey[600],
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
