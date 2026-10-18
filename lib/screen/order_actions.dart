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
      // Sent or ready for pick-up: the buyer confirms it arrived.
      if (order.status == 'shipped') {
        return [
          OrderCardAction(
            'Order Received',
            () => confirmReceived(context, order),
            kind: OrderActionKind.primary,
          ),
        ];
      }
      // A proposed new date is the one thing a buyer answers: accept it,
      // or cancel. (Message Farmer is on the order details screen.)
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
          '${order.buyerName}.',
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
      message: 'The item quantity will be returned to your inventory.',
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
    // The sheet owns its text fields (and disposes them once it has fully
    // closed), so nothing is used after it is gone.
    final report = await showAgriSheet<DelayReport>(
      context: context,
      isScrollControlled: true,
      title: 'Report Delay / Reschedule',
      builder: (_) => ReportDelaySheet(order: order),
    );
    if (report == null) return;

    final err = await _orders.reportDelay(
      id: order.id,
      reason: report.reason,
      otherReason: report.otherReason,
      proposedDate: report.proposedDate,
      note: report.note,
    );
    _snack(
      messenger,
      err ?? 'Delay reported. Waiting for ${order.buyerName} to respond.',
    );
  }

  /// Buyer: "Order Received" — they have the order, so it is completed
  /// (receipt issued, review unlocked, the farmer told).
  static Future<void> confirmReceived(
    BuildContext context,
    OrderInfo order,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showAgriConfirm(
      context: context,
      icon: Icons.inventory_2_outlined,
      title: 'Received your order?',
      message:
          'Confirm that you have received ${order.quantityLabel} of '
          '${order.productName}. This completes the order and issues its '
          'receipt.',
      confirmLabel: 'Received',
    );
    if (!ok) return;
    final err = await _orders.confirmReceived(order.id);
    _snack(messenger, err ?? 'Order completed. Your receipt is now available.');
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
      // Short labels, so the two buttons stay one line each.
      confirmLabel: 'Accept',
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
          'Your ${order.productName} order will be cancelled. This cannot '
          'be undone.',
      cancelLabel: 'Keep Order',
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
          ? '${order.productName} is ready for ${order.buyerName} to pick up.'
          : '${order.productName} is on its way to ${order.buyerName}.',
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

/// What the farmer filled in on the Report Delay sheet.
class DelayReport {
  final String reason;
  final String otherReason;
  final DateTime proposedDate;
  final String note;

  const DelayReport({
    required this.reason,
    required this.otherReason,
    required this.proposedDate,
    required this.note,
  });
}

/// Report Delay / Reschedule: the reason from a dropdown — "Other" opens a
/// box for the farmer's own words, at most 100 characters — the proposed
/// new date and an optional note. Send to Buyer is available once a date
/// is chosen (and, for Other, the reason written); it closes the sheet with
/// a [DelayReport].
class ReportDelaySheet extends StatefulWidget {
  final OrderInfo order;
  const ReportDelaySheet({super.key, required this.order});

  @override
  State<ReportDelaySheet> createState() => _ReportDelaySheetState();
}

class _ReportDelaySheetState extends State<ReportDelaySheet> {
  static const int otherMaxLength = 100;

  late String _reason = kOrderDelayReasons.containsKey(widget.order.delayReason)
      ? widget.order.delayReason
      : 'weather';
  late final _other = TextEditingController(text: widget.order.delayOtherReason)
    ..addListener(() => setState(() {}));
  late final _note = TextEditingController(text: widget.order.delayNote);
  late DateTime? _date = _initialDate();

  DateTime get _today => DateUtils.dateOnly(DateTime.now());

  DateTime? _initialDate() {
    final proposed = widget.order.delayProposedDate;
    return proposed == null || proposed.isBefore(_today) ? null : proposed;
  }

  @override
  void dispose() {
    _other.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _isOther => _reason == 'other';
  bool get _canSend =>
      _date != null && (!_isOther || _other.text.trim().isNotEmpty);

  // Every field is a white pill with a light border (the sheet itself is
  // light grey); the several-line note is a rounded capsule ([radius]).
  InputDecoration _field({String? hint, Widget? prefix, double radius = 30}) {
    OutlineInputBorder outline(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13.5, color: Colors.grey[500]),
      prefixIcon: prefix,
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      counterStyle: TextStyle(fontSize: 11, color: Colors.grey[500]),
      border: outline(Colors.grey.shade300),
      enabledBorder: outline(Colors.grey.shade300),
      focusedBorder: outline(AppTheme.mid, 1.4),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 7),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppTheme.dark,
      ),
    ),
  );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? _today,
      firstDate: _today,
      lastDate: _today.add(const Duration(days: 730)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final dateText = _date == null
        ? 'Choose a date'
        : MaterialLocalizations.of(context).formatMediumDate(_date!);
    // The sheet pads only its title: the same 18 px either side here, so
    // the text, the fields and the button all line up under it.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tell ${widget.order.buyerName} why this order is delayed and '
            'propose a new date. They can accept it, cancel, or message you.',
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey[700],
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),

          _label('Reason'),
          DropdownButtonFormField<String>(
            initialValue: _reason,
            isExpanded: true,
            // The list opens as the same white panel as every dropdown.
            dropdownColor: Colors.white,
            borderRadius: BorderRadius.circular(16),
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppTheme.dark,
            ),
            decoration: _field(),
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.dark,
            ),
            items: [
              for (final entry in kOrderDelayReasons.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _reason = value);
            },
          ),
          // "Other": what it is, in the farmer's own words.
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_isOther
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextField(
                      controller: _other,
                      maxLength: otherMaxLength,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _field(hint: 'Specify the reason'),
                    ),
                  ),
          ),
          SizedBox(height: _isOther ? 6 : 16),

          _label('Proposed new date'),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(30),
            child: InputDecorator(
              decoration:
                  _field(
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: 16, right: 8),
                      child: Icon(
                        Icons.calendar_today_outlined,
                        size: 18,
                        color: AppTheme.dark,
                      ),
                    ),
                  ).copyWith(
                    prefixIconConstraints: const BoxConstraints(minWidth: 0),
                    suffixIcon: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.dark,
                    ),
                  ),
              child: Text(
                dateText,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: _date == null ? FontWeight.w500 : FontWeight.w600,
                  color: _date == null ? Colors.grey[500] : AppTheme.dark,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _label('Note to the buyer (optional)'),
          TextField(
            controller: _note,
            maxLength: 200,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: _field(
              hint: 'Anything else the buyer should know',
              radius: 24,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _canSend
                ? () => Navigator.pop(
                    context,
                    DelayReport(
                      reason: _reason,
                      otherReason: _isOther ? _other.text.trim() : '',
                      proposedDate: _date!,
                      note: _note.text,
                    ),
                  )
                : null,
            style: AppTheme.primaryButton().copyWith(
              shape: const WidgetStatePropertyAll(StadiumBorder()),
            ),
            child: Text('Send to Buyer', style: AppTheme.buttonText()),
          ),
        ],
      ),
    );
  }
}
