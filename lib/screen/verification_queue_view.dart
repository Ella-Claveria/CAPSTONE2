import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:convert'; // Decodes Base64-embedded verification document images

import '../services/auth_service.dart';
import '../services/audit_log_service.dart';
import '../services/connectivity_service.dart';
import '../services/dashboard_analytics_service.dart';
import '../services/market_price_helpers.dart';
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
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verification Queue',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c.textPrimary),
          ),
          Text(
            'Review and approve agricultural credentials for new farmers.',
            style: TextStyle(color: c.textSecondary),
          ),
          const SizedBox(height: 24),

          Expanded(
            // Sourced from users (role == 'farmer' && approvalStatus ==
            // 'pending') — the same canonical query as
            // AuthService.getPendingFarmers() and the dashboard's pending
            // count — NOT from verificationDocs. A farmer whose
            // verificationDocs record is missing or malformed (an older
            // registration, an interrupted upload, etc.) still has a real
            // users/{uid} document, so they still need to show up here for
            // an admin to act on; querying verificationDocs directly would
            // silently exclude them, leaving no way to approve them short of
            // the Firebase Console.
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: AuthService().getPendingFarmers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error loading queue.', style: TextStyle(color: c.textSecondary)));
                }

                // "Pending" here means approvalStatus == 'pending' OR the
                // field is missing entirely (a legacy farmer account from
                // before this field existed) — the same "missing defaults
                // to pending" convention used everywhere else in the app,
                // so a legacy account is never invisible/stuck with no way
                // for an admin to ever approve them.
                final docs = (snapshot.data?.docs ?? []).where((d) {
                  final status = d.data()['approvalStatus'];
                  return status == null || status == 'pending';
                }).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No pending verifications at this time.',
                      style: TextStyle(fontSize: 18, color: c.textSecondary),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final uid = docs[index].id;
                    final profile = docs[index].data();
                    return _farmerApplicationCard(context, uid, profile);
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
  ) {
    // Supplementary only — submission date and the document image live on
    // verificationDocs, but the row (and the Approve/Reject actions below)
    // must never depend on this document existing.
    final verifStream =
        FirebaseFirestore.instance.collection('verificationDocs').doc(uid).snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: verifStream,
      builder: (context, verifSnap) {
        final verif = verifSnap.data?.data();

        final fullName = _firstNonEmpty([verif?['fullName'], profile['fullName'], profile['name']]) ??
            'Unknown Farmer';
        final email = (profile['email'] ?? '—').toString();
        final rawBarangay = profile['barangay']?.toString().trim();
        final barangay = (rawBarangay == null || rawBarangay.isEmpty) ? '—' : rawBarangay;
        final submittedAt = verif?['submittedAt'] as Timestamp?;
        final dateSubmitted =
            submittedAt != null ? DateFormat('MMM d, y').format(submittedAt.toDate()) : '—';
        final document = (verif?['document'] ?? '').toString();
        final farmerId = uid.length > 8 ? uid.substring(0, 8) : uid;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              backgroundColor: Colors.green[100],
              child: Icon(Icons.person, color: Colors.green[800]),
            ),
            title: Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
            isThreeLine: true,
            subtitle: Text(
              'ID: $farmerId  •  $email\nBarangay: $barangay  •  Submitted: $dateSubmitted',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'View full verification details',
                  icon: Icon(Icons.visibility_outlined, color: Colors.grey[700]),
                  onPressed: () => showFarmerVerificationDetails(context, uid: uid),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.image_search, color: Colors.blue),
                  label: const Text('View Doc'),
                  onPressed: document.isEmpty ? null : () => _showDocumentDialog(context, document),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  onPressed: () => approveFarmerAccount(context, uid, fullName),
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
      },
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
      final cleanBase64 = document.contains(',') ? document.split(',').last : document;

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
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  enabled: !loading,
                  decoration: const InputDecoration(
                    hintText: 'Reason for rejection (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: confirmColor, foregroundColor: Colors.white),
              onPressed: loading
                  ? null
                  : () async {
                      setDialogState(() => loading = true);
                      await action(reasonController?.text.trim());
                      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                    },
              child: loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
Future<void> approveFarmerAccount(BuildContext context, String uid, String farmerName) {
  return _confirmAndRun(
    context,
    title: 'Approve this Farmer account?',
    message: 'This farmer will be verified and able to list products and sell on AgriTrade+.',
    confirmLabel: 'Approve',
    confirmColor: Colors.green,
    action: (_) => _setFarmerApproval(context, uid, approved: true, farmerName: farmerName),
  );
}

Future<void> rejectFarmerAccount(BuildContext context, String uid, String farmerName) {
  return _confirmAndRun(
    context,
    title: 'Reject this Farmer verification?',
    message: 'The farmer will be notified that their application was not approved.',
    confirmLabel: 'Reject',
    confirmColor: Colors.red,
    withReason: true,
    action: (reason) =>
        _setFarmerApproval(context, uid, approved: false, reason: reason, farmerName: farmerName),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(kNoInternetActionMessage)));
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
        const SnackBar(content: Text('You cannot approve or reject your own account.')),
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
    await FirebaseFirestore.instance.collection('users').doc(uid).update(userUpdate);

    final docUpdate = <String, dynamic>{
      'status': status,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': adminUid,
    };
    if (!approved && reason != null && reason.isNotEmpty) {
      docUpdate['rejectionReason'] = reason;
    }
    await FirebaseFirestore.instance
        .collection('verificationDocs')
        .doc(uid)
        .set(docUpdate, SetOptions(merge: true));

    AuditLogService.log(
      approved ? AuditAction.approveFarmer : AuditAction.rejectFarmer,
      approved
          ? 'Approved farmer $farmerName.'
          : 'Rejected farmer $farmerName.${reason != null && reason.isNotEmpty ? ' Reason: $reason' : ''}',
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(approved ? 'Farmer approved successfully!' : 'Application rejected.')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating farmer: $e')));
  }
}

/// One-shot (not real-time — this backs a transient dialog, not a live
/// list) snapshot of a single farmer's marketplace activity, used only by
/// this screen's own verification detail dialog.
class _MarketplaceSummary {
  final int activeProducts;
  final int archivedProducts;
  final int completedOrders;
  final num totalSales;
  const _MarketplaceSummary({
    required this.activeProducts,
    required this.archivedProducts,
    required this.completedOrders,
    required this.totalSales,
  });
}

Future<_MarketplaceSummary> _loadMarketplaceSummary(String uid) async {
  final products =
      await FirebaseFirestore.instance.collection('products').where('farmerId', isEqualTo: uid).get();
  var active = 0, archived = 0;
  for (final p in products.docs) {
    if ((p.data()['isArchived'] ?? false) == true) {
      archived++;
    } else {
      active++;
    }
  }

  final orders =
      await FirebaseFirestore.instance.collection('orders').where('sellerId', isEqualTo: uid).get();
  final completedCount = orders.docs
      .where((o) => (o.data()['status'] ?? '').toString().toLowerCase() == 'completed')
      .length;
  // TOTAL TRANSACTION VALUE — same definition/formula as the platform-
  // wide KPI tile (DashboardAnalyticsService.platformTransactionTotal),
  // just scoped to this one farmer's own orders.
  final totalSales = DashboardAnalyticsService.platformTransactionTotal(orders.docs);

  return _MarketplaceSummary(
    activeProducts: active,
    archivedProducts: archived,
    completedOrders: completedCount,
    totalSales: totalSales,
  );
}

/// Opens the full verification/profile detail dialog for one farmer — used
/// by the Verification Queue's pending list and the Home dashboard's
/// "Recent Verification Requests" table, so both stay backed by the same
/// live data and the same approve/reject actions. The Farmer List page has
/// its own, separate detail dialog and does not use this one.
Future<void> showFarmerVerificationDetails(BuildContext context, {required String uid}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _FarmerVerificationDetailDialog(uid: uid),
  );
}

class _FarmerVerificationDetailDialog extends StatelessWidget {
  final String uid;
  const _FarmerVerificationDetailDialog({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, userSnap) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('verificationDocs').doc(uid).snapshots(),
          builder: (context, verifSnap) {
            if (userSnap.hasError || verifSnap.hasError) {
              return AlertDialog(
                title: const Text('Something went wrong'),
                content: const Text('Could not load this farmer\'s details. Please try again.'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                ],
              );
            }
            if (!userSnap.hasData || !verifSnap.hasData) {
              return const AlertDialog(
                content: SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            final user = userSnap.data!.data();
            if (user == null) {
              return AlertDialog(
                title: const Text('Account Not Found'),
                content: const Text('This farmer\'s account could not be found. It may have been removed.'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                ],
              );
            }
            final verif = verifSnap.data!.data();

            final fullName = _firstNonEmpty([verif?['fullName'], user['fullName'], user['name']]) ??
                'Unknown Farmer';
            final email = (user['email'] ?? '—').toString();
            final barangay = _firstNonEmpty([user['barangay']]) ?? '—';
            final municipality = _firstNonEmpty([user['municipality']]) ?? '—';
            final phone = _firstNonEmpty([user['phone']]) ?? '—';
            final approvalStatus = (user['approvalStatus'] ?? 'pending').toString();
            final statusLabel = approvalStatus.isEmpty
                ? 'Pending'
                : '${approvalStatus[0].toUpperCase()}${approvalStatus.substring(1)}';
            final submittedAt = verif?['submittedAt'] as Timestamp?;
            final dateSubmitted =
                submittedAt != null ? DateFormat('MMM d, y – h:mm a').format(submittedAt.toDate()) : '—';
            final reviewedAt = user['reviewedAt'] as Timestamp?;
            final dateReviewed =
                reviewedAt != null ? DateFormat('MMM d, y – h:mm a').format(reviewedAt.toDate()) : '—';
            final reviewedByUid = _firstNonEmpty([user['reviewedBy']]);
            final reviewedBy = reviewedByUid == null
                ? '—'
                : (reviewedByUid.length > 8 ? reviewedByUid.substring(0, 8) : reviewedByUid);
            final document = (verif?['document'] ?? '').toString();
            final rejectionReason = (verif?['rejectionReason'] ?? '').toString();

            return AlertDialog(
              title: Text(fullName),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('Profile'),
                      _detailRow('Farmer ID', uid),
                      _detailRow('Email', email),
                      _detailRow('Barangay', barangay),
                      _detailRow('Municipality', municipality),
                      _detailRow('Phone Number', phone),
                      const SizedBox(height: 10),
                      _sectionLabel('Verification'),
                      _detailRow('Status', statusLabel),
                      _detailRow('Date Submitted', dateSubmitted),
                      _detailRow('Reviewed At', dateReviewed),
                      _detailRow('Reviewed By', reviewedBy),
                      if (approvalStatus == 'rejected' && rejectionReason.isNotEmpty)
                        _detailRow('Rejection Reason', rejectionReason),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.image_search, color: Colors.blue),
                        label: const Text('View Submitted Document'),
                        onPressed: document.isEmpty ? null : () => _showDocumentDialog(context, document),
                      ),
                      if (document.isEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'No verification document was submitted for this account.',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 10),
                      FutureBuilder<_MarketplaceSummary>(
                        future: _loadMarketplaceSummary(uid),
                        builder: (context, activitySnap) {
                          if (activitySnap.connectionState != ConnectionState.done) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          }
                          if (activitySnap.hasError || !activitySnap.hasData) {
                            return Text(
                              'Could not load marketplace activity.',
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            );
                          }
                          final a = activitySnap.data!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionLabel('Marketplace Summary'),
                              _detailRow('Active Products', '${a.activeProducts}'),
                              _detailRow('Archived Products', '${a.archivedProducts}'),
                              _detailRow('Completed Orders', '${a.completedOrders}'),
                              _detailRow('Total Sales', formatPeso(a.totalSales)),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                if (approvalStatus == 'pending') ...[
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () {
                      Navigator.of(context).pop();
                      rejectFarmerAccount(context, uid, fullName);
                    },
                    child: const Text('Reject'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
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
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.grey[600], letterSpacing: 0.4),
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
            child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700])),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
