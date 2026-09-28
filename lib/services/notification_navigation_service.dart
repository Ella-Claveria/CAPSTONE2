import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart' show rootNavigatorKey;
import '../screen/buyer_marketplace_screen.dart';
import '../screen/chat_screen.dart';
import '../screen/farmer_home_screen.dart';
import '../screen/pending_approval_screen.dart';
import 'connectivity_service.dart';

/// Where a notification of a given `type` should take the user. Used by
/// three entry points that must never drift out of sync on this decision:
/// tapping a row in [NotificationsScreen], tapping a foreground local
/// notification, and tapping the system tray notification from background
/// or a cold start (see PushNotificationService).
class NotificationNavigationService {
  const NotificationNavigationService._();

  static Future<void> open({
    required String type,
    required Map<String, dynamic> data,
  }) async {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;

    switch (type) {
      case 'new_order':
      case 'order_status':
        final orderId = data['orderId']?.toString();
        if (orderId == null || orderId.isEmpty) return;
        await _openOrder(context, orderId);
        return;

      case 'chat_message':
        final conversationId = data['conversationId']?.toString();
        final senderId = data['senderId']?.toString();
        if (conversationId == null || senderId == null) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              conversationId: conversationId,
              otherUserId: senderId,
              otherUserName: data['senderName']?.toString() ?? 'User',
            ),
          ),
        );
        return;

      case 'verification_status':
        // PendingApprovalScreen already reflects pending/approved/rejected
        // live and auto-advances to Farmer Home once approved — the same
        // screen used during the original onboarding wait.
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const PendingApprovalScreen()));
        return;

      case 'moderation_warning':
        final accountStatus = data['accountStatus']?.toString();
        if (accountStatus != null && accountStatus.isNotEmpty) {
          // notifyAccountModeration (suspend/ban) reuses this same type but
          // carries no reportId/productId — there's no report to fetch, so
          // it needs its own dialog instead of falling into
          // _showModerationNotice's "report no longer available" fallback.
          await _showAccountModerationNotice(context);
          return;
        }
        final reportId = data['reportId']?.toString();
        final productId = data['productId']?.toString();
        await _showModerationNotice(context, reportId: reportId, productId: productId);
        return;

      default:
        return;
    }
  }

  /// Account suspended/banned (notifyAccountModeration) — reads the current
  /// user doc live rather than trusting the notification payload, since an
  /// admin may have already reversed the decision by the time this is
  /// tapped, and only the live doc has the reason text.
  static Future<void> _showAccountModerationNotice(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    Map<String, dynamic>? user;
    try {
      if (uid != null) {
        final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        user = snap.data();
      }
    } catch (_) {
      user = null;
    }
    if (!context.mounted) return;

    final accountStatus = user?['accountStatus']?.toString();
    final stillSuspended = accountStatus == 'suspended';
    final stillBanned = accountStatus == 'banned';
    final suspensionReason = user?['suspensionReason']?.toString();
    final banReason = user?['banReason']?.toString();
    final reason = stillSuspended ? suspensionReason : banReason;

    final String title;
    final String message;
    if (stillSuspended) {
      title = 'Account Suspended';
      message = 'Your AgriTrade+ account has been temporarily suspended following an Admin review.';
    } else if (stillBanned) {
      title = 'Account Deactivated';
      message = 'Your AgriTrade+ account has been deactivated following an Admin review.';
    } else {
      // Cleared back to active since the notification was sent.
      title = 'Account Status Update';
      message = 'This has since been resolved — your account is in good standing.';
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if ((stillSuspended || stillBanned) && reason != null && reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Reason: $reason'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Shows the farmer what was reviewed and what Admin decided — reason,
  /// description, the related listing if any, and the outcome — without
  /// exposing who filed the report. Reads the report (and, for a
  /// listing-targeted warning, the product) directly rather than trusting
  /// the notification payload, since Admin may still amend `adminNotes`.
  static Future<void> _showModerationNotice(
    BuildContext context, {
    String? reportId,
    String? productId,
  }) async {
    Map<String, dynamic>? report;
    Map<String, dynamic>? product;
    try {
      if (reportId != null && reportId.isNotEmpty) {
        final snap = await FirebaseFirestore.instance.collection('reports').doc(reportId).get();
        report = snap.data();
      }
      if (productId != null && productId.isNotEmpty) {
        final snap = await FirebaseFirestore.instance.collection('products').doc(productId).get();
        product = snap.data();
      }
    } catch (_) {
      report = null;
      product = null;
    }
    if (!context.mounted) return;

    final reason = (report?['issueType'] ?? report?['reason'])?.toString();
    final description = report?['description']?.toString();
    final productName = product?['name']?.toString() ?? report?['productName']?.toString();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(productName != null ? 'Listing Warning' : 'Account Warning'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (productName != null) ...[
              Text('Listing: $productName', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
            ],
            if (reason != null && reason.isNotEmpty) ...[
              Text('Reason: $reason'),
              const SizedBox(height: 6),
            ],
            if (description != null && description.isNotEmpty)
              Text(description)
            else if (report == null)
              const Text('This report is no longer available.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static Future<void> _openOrder(BuildContext context, String orderId) async {
    Map<String, dynamic>? order;
    try {
      final snap = await FirebaseFirestore.instance.collection('orders').doc(orderId).get();
      order = snap.data();
    } catch (_) {
      order = null;
    }
    if (!context.mounted) return;

    if (order == null) {
      final online = await ConnectivityService.instance.checkNow();
      if (!context.mounted) return;
      _showMessage(
        context,
        online
            ? 'This order is no longer available.'
            : 'Could not load this order. Check your connection and try again.',
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isSeller = order['sellerId'] == uid;

    // The app always keeps exactly one Farmer/Buyer Home at the bottom of
    // the navigation stack (see AuthRoutingService / app_router.dart), so
    // popping to it and flipping its tab index in place is the correct
    // reuse of the existing routing system — never a second, stacked Home.
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (isSeller) {
      globalFarmerTabIndex.value = 2; // Orders tab on Farmer Home
    } else {
      globalMarketplaceIndex.value = 2; // Orders tab on Buyer Home
    }

    await Future.delayed(const Duration(milliseconds: 250));
    if (!context.mounted) return;
    await _showOrderSummary(context, order, isSeller: isSeller);
  }

  static Future<void> _showOrderSummary(
    BuildContext context,
    Map<String, dynamic> order, {
    required bool isSeller,
  }) async {
    const dark = Color(0xFF1B5E20);
    final name = order['productName']?.toString() ?? 'Product';
    final counterpart = isSeller
        ? (order['buyerName']?.toString() ?? 'Buyer')
        : (order['sellerName']?.toString() ?? 'Farmer');
    final qty = order['quantityLabel']?.toString() ??
        '${order['quantity'] ?? ''} ${order['unit'] ?? ''}'.trim();
    final status = (order['status'] ?? 'pending').toString();
    final totalRaw = order['total'];
    final total = totalRaw is num ? totalRaw : (num.tryParse('$totalRaw') ?? 0);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${isSeller ? 'Buyer' : 'Farmer'}: $counterpart'),
            if (qty.isNotEmpty) ...[const SizedBox(height: 6), Text('Quantity: $qty')],
            const SizedBox(height: 6),
            Text('Total: ₱${total.toStringAsFixed(0)}'),
            const SizedBox(height: 6),
            Text(
              'Status: ${status.isEmpty ? status : '${status[0].toUpperCase()}${status.substring(1)}'}',
              style: const TextStyle(fontWeight: FontWeight.w600, color: dark),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
