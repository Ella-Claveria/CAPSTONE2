import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/message_service.dart';
import '../services/order_format.dart';
import '../services/order_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/order_card.dart';
import 'add_review_screen.dart';
import 'chat_screen.dart';
import 'order_details_screen.dart';
import 'order_receipt_screen.dart';

/// Everything a user can do to an order from the Orders list, the order
/// details screen or a receipt card in Messages. The business rules stay in
/// [OrderService] / [MessageService]; this only confirms, calls them and
/// reports the outcome, so every entry point behaves the same.
class OrderActions {
  const OrderActions._();

  static final OrderService _orders = OrderService();
  static final MessageService _messages = MessageService();

  static void _snack(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: AppTheme.dark,
        content: Text(message),
      ),
    );
  }

  /// The role-specific buttons for [order], most important last. Shared by
  /// the list card and the details screen so they never disagree. Only
  /// transitions the order workflow actually supports are offered: the
  /// farmer moves an order forward (or reports a delay); a buyer only
  /// answers a proposed new date — accept it or cancel.
  static List<OrderCardAction> actionsFor(
    BuildContext context,
    OrderInfo order,
    OrderRole role,
  ) {
    if (order.isCompleted) {
      return [
        if (role == OrderRole.buyer && !order.reviewed)
          OrderCardAction('Review', () => review(context, order)),
        OrderCardAction(
          'View Receipt',
          () => viewReceipt(context, order.id),
          kind: OrderActionKind.primary,
        ),
      ];
    }
    if (role == OrderRole.buyer) {
      // A proposed new date is the one thing a buyer answers: accept it,
      // or cancel. (Message Farmer is the card's own message button.)
      if (!order.isDelayed) return const [];
      return [
        OrderCardAction(
          'Cancel Order',
          () => cancelDelayed(context, order),
          kind: OrderActionKind.destructive,
        ),
        OrderCardAction(
          'Accept New Date',
          () => acceptNewDate(context, order),
          kind: OrderActionKind.primary,
        ),
      ];
    }
    return switch (order.status) {
      'pending' => [
        OrderCardAction(
          'Reject',
          () => reject(context, order),
          kind: OrderActionKind.destructive,
        ),
        OrderCardAction(
          'Accept',
          () => accept(context, order),
          kind: OrderActionKind.primary,
        ),
      ],
      'confirmed' => [
        // Weather, transport, supply… — propose a new date instead of
        // letting the order silently run late.
        OrderCardAction(
          order.isDelayed ? 'Update Delay' : 'Report Delay',
          () => reportDelay(context, order),
        ),
        OrderCardAction(
          order.isPickup ? 'Ready for Pick-up' : 'Mark as Shipped',
          () => markShipped(context, order),
          kind: OrderActionKind.primary,
        ),
      ],
      'shipped' => [
        OrderCardAction(
          'Mark as Completed',
          () => markCompleted(context, order),
          kind: OrderActionKind.primary,
        ),
      ],
      _ => const [],
    };
  }

  static Future<void> accept(BuildContext context, OrderInfo order) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showAgriConfirm(
      context: context,
      icon: Icons.assignment_turned_in_outlined,
      title: 'Accept this order?',
      message:
          '${order.quantityLabel} of ${order.productName} for '
          '${order.buyerName}. The buyer will be notified.',
      confirmLabel: 'Accept',
    );
    if (!ok) return;
    final err = await _orders.updateStatus(order.id, 'confirmed');
    _snack(messenger, err ?? 'Order confirmed.');
  }

  static Future<void> reject(BuildContext context, OrderInfo order) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showAgriConfirm(
      context: context,
      icon: Icons.cancel_outlined,
      tone: AgriTone.destructive,
      title: 'Reject this order?',
      message:
          'The buyer will be notified and the item quantity will be returned to your inventory.',
      confirmLabel: 'Reject',
    );
    if (!ok) return;
    final err = await _orders.rejectOrder(order.id);
    _snack(messenger, err ?? 'Order rejected.');
  }

  // ---- Delay / reschedule ----

  /// Farmer: "Report Delay / Reschedule" on a confirmed order — pick a
  /// reason, propose a new date and optionally add a short note. The buyer
  /// is notified and decides; the order itself (id, stock, prices) is left
  /// exactly as it is.
  static Future<void> reportDelay(BuildContext context, OrderInfo order) async {
    final messenger = ScaffoldMessenger.of(context);
    final noteController = TextEditingController(text: order.delayNote);
    var reason = kOrderDelayReasons.containsKey(order.delayReason)
        ? order.delayReason
        : 'weather';
    DateTime? proposed = order.delayProposedDate;
    final today = DateUtils.dateOnly(DateTime.now());
    if (proposed != null && proposed.isBefore(today)) proposed = null;

    final submitted = await showAgriSheet<bool>(
      context: context,
      isScrollControlled: true,
      title: 'Report Delay / Reschedule',
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tell ${order.buyerName} why this order is delayed and '
                'propose a new date. They can accept it, cancel, or message '
                'you.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[800]),
              ),
              const SizedBox(height: 14),
              const Text(
                'Reason',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in kOrderDelayReasons.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: reason == entry.key,
                      showCheckmark: false,
                      selectedColor: AppTheme.dark,
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: reason == entry.key
                            ? Colors.white
                            : AppTheme.dark,
                      ),
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: AppTheme.dark.withValues(alpha: 0.3),
                        ),
                      ),
                      onSelected: (_) =>
                          setSheetState(() => reason = entry.key),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Proposed new date',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: sheetContext,
                    initialDate: proposed ?? today,
                    firstDate: today,
                    lastDate: today.add(const Duration(days: 730)),
                  );
                  if (picked != null) setSheetState(() => proposed = picked);
                },
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(
                  proposed == null
                      ? 'Choose a date'
                      : MaterialLocalizations.of(
                          sheetContext,
                        ).formatMediumDate(proposed!),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.dark,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  side: BorderSide(color: Colors.grey.shade400),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: noteController,
                maxLength: 200,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Note to the buyer (optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: proposed == null
                    ? null
                    : () => Navigator.pop(sheetContext, true),
                style: AppTheme.primaryButton(),
                child: Text('Send to Buyer', style: AppTheme.buttonText()),
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );

    final note = noteController.text;
    noteController.dispose();
    if (submitted != true || proposed == null) return;

    final err = await _orders.reportDelay(
      id: order.id,
      reason: reason,
      proposedDate: proposed!,
      note: note,
    );
    _snack(messenger, err ?? 'Delay reported. The buyer has been notified.');
  }

  /// Buyer: accept the farmer's proposed date.
  static Future<void> acceptNewDate(
    BuildContext context,
    OrderInfo order,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final date = order.delayProposedDate;
    final ok = await showAgriConfirm(
      context: context,
      icon: Icons.event_available_outlined,
      title: 'Accept the new date?',
      message:
          '${order.sellerName} proposed '
          '${date == null ? 'a new date' : MaterialLocalizations.of(context).formatMediumDate(date)} '
          'for your ${order.productName} order. Your order stays as it is — '
          'only the date changes.',
      confirmLabel: 'Accept New Date',
    );
    if (!ok) return;
    final err = await _orders.acceptProposedDate(order.id);
    _snack(messenger, err ?? 'New date accepted.');
  }

  /// Buyer: cancel an order instead of accepting its new date.
  static Future<void> cancelDelayed(
    BuildContext context,
    OrderInfo order,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showAgriConfirm(
      context: context,
      icon: Icons.cancel_outlined,
      tone: AgriTone.destructive,
      title: 'Cancel this order?',
      message:
          'Your ${order.productName} order will be cancelled and the farmer '
          'will be notified. This cannot be undone.',
      confirmLabel: 'Cancel Order',
    );
    if (!ok) return;
    final err = await _orders.cancelDelayedOrder(order.id);
    _snack(messenger, err ?? 'Order cancelled.');
  }

  static Future<void> markShipped(BuildContext context, OrderInfo order) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showAgriConfirm(
      context: context,
      icon: order.isPickup
          ? Icons.inventory_2_outlined
          : Icons.local_shipping_outlined,
      title: order.isPickup ? 'Ready for pick-up?' : 'Mark as shipped?',
      message: order.isPickup
          ? '${order.productName} is ready for ${order.buyerName} to pick up. The buyer will be notified.'
          : '${order.productName} is on its way to ${order.buyerName}. The buyer will be notified.',
      confirmLabel: 'Confirm',
    );
    if (!ok) return;
    final err = await _orders.updateStatus(order.id, 'shipped');
    _snack(
      messenger,
      err ??
          (order.isPickup
              ? 'Order marked ready for pick-up.'
              : 'Order marked shipped.'),
    );
  }

  static Future<void> markCompleted(
    BuildContext context,
    OrderInfo order,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showAgriConfirm(
      context: context,
      icon: Icons.task_alt_rounded,
      title: 'Mark as completed?',
      message:
          '${order.buyerName} has received ${order.productName}. This '
          'finalizes the transaction and issues its receipt, and cannot be undone.',
      confirmLabel: 'Complete',
    );
    if (!ok) return;
    final err = await _orders.updateStatus(order.id, 'completed');
    _snack(messenger, err ?? 'Order completed. The receipt is now available.');
    // Tied to the status change itself, not to anyone opening a screen.
    if (err == null) unawaited(_deliverReceipt(order));
  }

  /// Puts the receipt card of a just-completed order into the farmer–buyer
  /// conversation. The issueOrderReceipt Cloud Function does the same from
  /// the status change; whichever gets there first wins and the other finds
  /// the message already there (its id is derived from the order id, and
  /// Firestore rules refuse to overwrite it) — so it is sent exactly once.
  static Future<String?> _deliverReceipt(OrderInfo order) async {
    try {
      final conversationId = await _messages.ensureOrderConversation(
        sellerId: order.sellerId,
        sellerName: order.sellerName,
        buyerId: order.buyerId,
        buyerName: order.buyerName,
        productId: order.productId,
        productName: order.productName,
        productImageUrl: order.imageUrl,
      );
      try {
        await _messages.sendReceiptMessage(
          conversationId: conversationId,
          buyerId: order.buyerId,
          orderId: order.id,
          orderDisplayId: order.displayId,
          receiptNumber: receiptNumberFor(order.id, order.createdAt),
          productId: order.productId,
          productName: order.productName,
          subtotal: order.subtotal,
          total: order.grandTotal,
        );
      } catch (_) {
        // Already sent by the system in the meantime — it's in the chat.
      }
      return conversationId;
    } catch (_) {
      return null; // Offline etc. — the Cloud Function still delivers it.
    }
  }

  static void openDetails(
    BuildContext context,
    OrderInfo order,
    OrderRole role,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OrderDetailsScreen(orderId: order.id, role: role, initial: order),
      ),
    );
  }

  static void viewReceipt(BuildContext context, String orderId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OrderReceiptScreen(orderId: orderId)),
    );
  }

  /// Opens the farmer–buyer conversation for [order] (the existing one if
  /// they have already chatted).
  static Future<void> message(
    BuildContext context,
    OrderInfo order,
    OrderRole role, {
    bool withReceipt = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final String conversationId;
    try {
      conversationId = await _messages.ensureOrderConversation(
        sellerId: order.sellerId,
        sellerName: order.sellerName,
        buyerId: order.buyerId,
        buyerName: order.buyerName,
        productId: order.productId,
        productName: order.productName,
        productImageUrl: order.imageUrl,
      );
    } catch (e) {
      _snack(
        messenger,
        e is StateError ? e.message : 'Could not open the conversation.',
      );
      return;
    }

    if (withReceipt && role == OrderRole.farmer && order.isCompleted) {
      await _deliverReceipt(order);
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conversationId,
          otherUserId: order.otherPartyId(role),
          otherUserName: order.otherPartyName(role),
          isFarmer: role == OrderRole.farmer,
          productId: order.productId,
          productName: order.productName,
          productImageUrl: order.imageUrl,
        ),
      ),
    );
  }

  /// Opens the review form for a completed order — only for the buyer of
  /// that exact order. (ReviewService and Firestore rules enforce the same.)
  /// Returns true if a review was submitted.
  static Future<bool> review(BuildContext context, OrderInfo order) async {
    final messenger = ScaffoldMessenger.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid != order.buyerId) {
      _snack(messenger, 'Only the buyer of this order can review it.');
      return false;
    }
    if (!order.isCompleted) {
      _snack(
        messenger,
        'You can review this product once the order is completed.',
      );
      return false;
    }
    if (order.productId.isEmpty || order.sellerId.isEmpty) {
      _snack(messenger, 'Missing product info for review.');
      return false;
    }
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddReviewScreen(
          orderId: order.id,
          productId: order.productId,
          productName: order.productName,
          sellerId: order.sellerId,
          productImage: order.imageUrl,
        ),
      ),
    );
    return done == true;
  }
}
