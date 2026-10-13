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
import 'admin_dashboard_screen.dart' show AdminThemeScope;

/// Pending Farmer applications only — role == 'farmer' && approvalStatus ==
/// 'pending'. Approved Farmers have their own dedicated page/nav item, see
/// farmer_list_view.dart (a fully separate screen — it does not share this
/// file's dialog or data loaders); this screen's job stays exactly what it
/// was: the queue of applications still awaiting an admin decision.
class VerificationQueueView extends StatelessWidget {
  const VerificationQueueView({super.key});

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

                    if (docs.isEmpty) {
                      return Center(
                        child: Text(
                          'No pending verifications at this time.',
                          style: TextStyle(
                            fontSize: 15,
                            color: c.textSecondary,
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final uid = docs[index].id;
                        final profile = docs[index].data();
                        final farmerId = farmerIdOf(profile, verifByUid[uid]);
                        return _farmerApplicationCard(
                          context,
                          uid,
                          profile,
                          verifByUid[uid],
                          sameFarmerId: [
                            for (final other
                                in (namesByFarmerId[farmerId] ?? const {})
                                    .entries)
                              if (other.key != uid) other.value,
                          ],
                        );
                      },
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

  Widget _farmerApplicationCard(
    BuildContext context,
    String uid,
    Map<String, dynamic> profile,
    Map<String, dynamic>? verif, {
    List<String> sameFarmerId = const [],
  }) {
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

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: Colors.green[100],
          child: Icon(Icons.person, color: Colors.green[800]),
        ),
        title: Text(
          fullName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        isThreeLine: true,
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                text: 'RSBA No.: ',
                children: [
                  TextSpan(
                    text: farmerId ?? kNoFarmerId,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: farmerId == null ? Colors.red[700] : null,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$email  •  Barangay: $barangay  •  Submitted: $dateSubmitted',
            ),
            if (sameFarmerId.isNotEmpty)
              Text(
                'This RSBA No. is also on another farmer account: '
                '${sameFarmerId.join(', ')}.',
                style: TextStyle(color: Colors.red[700], fontSize: 12.5),
              ),
            if (nothingToCheck)
              Text(
                'No RSBA No. was submitted, so there is nothing to check '
                'this application against.',
                style: TextStyle(color: Colors.red[700], fontSize: 12.5),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'View full verification details',
              icon: Icon(Icons.visibility_outlined, color: Colors.grey[700]),
              onPressed: () => showFarmerVerificationDetails(context, uid: uid),
            ),
            // Only an older application has a document; the RSBA number
            // took its place on the registration form.
            if (document.isNotEmpty) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.image_search),
                label: const Text('View Doc'),
                onPressed: () => _showDocumentDialog(context, document),
              ),
              const SizedBox(width: 8),
            ],
            ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Approve'),
              onPressed: nothingToCheck
                  ? null
                  : () => approveFarmerAccount(context, uid, fullName),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.close, color: Colors.red),
              label: const Text('Reject', style: TextStyle(color: Colors.red)),
              onPressed: () => rejectFarmerAccount(context, uid, fullName),
            ),
          ],
        ),
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
