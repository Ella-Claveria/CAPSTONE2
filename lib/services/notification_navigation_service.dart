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

      default:
        return;
    }
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
