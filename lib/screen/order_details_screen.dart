import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/market_price_helpers.dart';
import '../services/order_format.dart';
import '../theme/app_theme.dart';
import '../widgets/order_card.dart';
import '../widgets/profile_avatar.dart';
import 'order_actions.dart';

/// The complete summary of one order, for either side: status, product,
/// the other party, fulfillment, payment and timeline. Stays live — a
/// status change (or the receipt becoming available) shows up without
/// reopening the screen.
class OrderDetailsScreen extends StatefulWidget {
  final String orderId;
  final OrderRole role;

  /// The order as the caller already has it, shown until the live copy
  /// arrives.
  final OrderInfo? initial;

  const OrderDetailsScreen({
    super.key,
    required this.orderId,
    required this.role,
    this.initial,
  });

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _orderStream =
      FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .snapshots();

  late OrderInfo? _order = widget.initial;

  // The other party's public profile (photo + general area only).
  // Loaded once per other-party uid, not on every rebuild.
  Future<Map<String, dynamic>>? _otherProfile;
  String _profileFor = '';

  OrderRole get _role => widget.role;

  Future<Map<String, dynamic>> _loadProfile(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('publicProfiles')
          .doc(uid)
          .get();
      return snap.data() ?? const {};
    } catch (_) {
      return const {};
    }
  }

  String _area(Map<String, dynamic> profile) =>
      [profile['barangay'], profile['municipality']]
          .map((v) => (v ?? '').toString().trim())
          .where((v) => v.isNotEmpty)
          .join(', ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F5),
      appBar: AppBar(
        title: const Text('Order Details'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.dark,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        titleTextStyle: AppTheme.heading(17).copyWith(color: AppTheme.dark),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _orderStream,
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.exists) {
            _order = OrderInfo.fromDoc(snapshot.data!);
          }
          final order = _order;
          if (order == null) {
            return Center(
              child: snapshot.hasError || snapshot.hasData
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'This order could not be loaded.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppTheme.dark,
                      ),
                    ),
            );
          }

          final otherId = order.otherPartyId(_role);
          if (otherId.isNotEmpty && _profileFor != otherId) {
            _profileFor = otherId;
            _otherProfile = _loadProfile(otherId);
          }

          final actions = OrderActions.actionsFor(context, order, _role);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                  children: [
                    _statusHeader(order),
                    if (order.isDelayed || order.delayAccepted)
                      _delaySection(order),
                    _productSummary(order),
                    _otherParty(order),
                    _fulfillment(order),
                    _payment(order),
                    if (order.isCompleted) _receipt(order),
                    _timeline(order),
                  ],
                ),
              ),
              if (actions.isNotEmpty) _actionBar(actions),
            ],
          );
        },
      ),
    );
  }

  // ---- Building blocks ----

  Widget _section({String? title, required Widget child}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(
            title.toUpperCase(),
            style: GoogleFonts.montserrat(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 10),
        ],
        child,
      ],
    ),
  );

  Widget _line(
    String label,
    String value, {
    bool strong = false,
    Color? color,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: GoogleFonts.montserrat(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.montserrat(
              fontSize: strong ? 14.5 : 12.5,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              color: color ?? Colors.black87,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _note(String text) => Text(
    text,
    style: GoogleFonts.montserrat(
      fontSize: 11.5,
      color: Colors.grey[600],
      height: 1.4,
    ),
  );

  // ---- Sections ----

  // ---- Delay / reschedule ----
  // Shown on a confirmed order the farmer has reported as delayed: the
  // reason, the proposed new date, the farmer's note, and what happens
  // next. Once the buyer accepts, it stays as a record of the agreed date.
  Widget _delaySection(OrderInfo order) {
    final proposed = order.delayProposedDate;
    final proposedLabel = proposed == null
        ? 'To be confirmed'
        : MaterialLocalizations.of(context).formatMediumDate(proposed);
    final waiting = order.isDelayed;
    final warning = Colors.orange.shade800;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: waiting
            ? Colors.orange.withValues(alpha: 0.08)
            : const Color(0xFFF1F8F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: waiting ? Colors.orange.shade200 : const Color(0xFFC8E6C9),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                waiting
                    ? Icons.schedule_rounded
                    : Icons.event_available_outlined,
                size: 19,
                color: waiting ? warning : AppTheme.dark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  waiting ? 'Delayed' : 'Rescheduled',
                  style: GoogleFonts.montserrat(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: waiting ? warning : AppTheme.dark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _line('Reason', order.delayReasonLabel),
          _line(waiting ? 'Proposed new date' : 'New date', proposedLabel),
          if (order.delayNote.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '“${order.delayNote}”',
              style: GoogleFonts.montserrat(
                fontSize: 12.5,
                height: 1.4,
                fontStyle: FontStyle.italic,
                color: Colors.black87,
              ),
            ),
          ],
          const SizedBox(height: 6),
          _note(
            waiting
                ? (_role == OrderRole.buyer
                      ? 'Accept the new date, cancel the order, or message '
                            'the farmer. Your order, quantity and price stay '
                            'the same.'
                      : 'Waiting for the buyer to accept the new date. The '
                            'order, its stock and its price are unchanged.')
                : 'The buyer accepted this date.',
          ),
        ],
      ),
    );
  }

  Widget _statusHeader(OrderInfo order) {
    final color = orderStatusColor(order.status);
    final label = order.status == 'shipped' && order.isPickup
        ? 'Ready for pick-up'
        : '${order.status[0].toUpperCase()}${order.status.substring(1)}';
    final icon = switch (order.status) {
      'confirmed' => Icons.assignment_turned_in_outlined,
      'shipped' =>
        order.isPickup
            ? Icons.inventory_2_outlined
            : Icons.local_shipping_outlined,
      'completed' => Icons.task_alt_rounded,
      'rejected' || 'cancelled' => Icons.cancel_outlined,
      _ => Icons.pending_actions_outlined,
    };
    return _section(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Order #${order.displayId}',
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                if (order.createdAt != null)
                  Text(
                    'Placed ${formatOrderDateTimeLong(order.createdAt!)}',
                    style: GoogleFonts.montserrat(
                      fontSize: 11.5,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _productSummary(OrderInfo order) => _section(
    title: 'Product Summary',
    child: Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OrderThumbnail(order, size: 64),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.productName,
                    style: GoogleFonts.montserrat(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  OrderPricingTag(order),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _line('Quantity', order.quantityLabel),
        if (order.unit.isNotEmpty) _line('Unit', order.unit),
        if (order.unitPrice != null) _line('Unit price', order.unitPriceLabel),
        _line('Subtotal', formatPeso(order.subtotal)),
      ],
    ),
  );

  Widget _otherParty(OrderInfo order) {
    final name = order.otherPartyName(_role);
    return _section(
      title: _role == OrderRole.farmer ? 'Buyer' : 'Farmer',
      child: FutureBuilder<Map<String, dynamic>>(
        future: _otherProfile,
        builder: (context, snapshot) {
          final profile = snapshot.data ?? const <String, dynamic>{};
          final area = _area(profile);
          return Row(
            children: [
              ProfileAvatar(
                photoUrl: profile['photoUrl']?.toString(),
                name: name,
                radius: 20,
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
                      style: GoogleFonts.montserrat(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (area.isNotEmpty) _note(area),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OrderActionButton(
                OrderCardAction(
                  _role == OrderRole.farmer
                      ? 'Message Buyer'
                      : 'Message Farmer',
                  () => OrderActions.message(context, order, _role),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _fulfillment(OrderInfo order) {
    final feeParty = _role == OrderRole.farmer ? 'buyer' : 'seller';
    return _section(
      title: 'Fulfillment Summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _line(
            'Method',
            order.fulfillmentLabel.isEmpty
                ? 'Not specified'
                : order.fulfillmentLabel,
          ),
          if (order.isDelivery) ...[
            _line(
              'Delivery fee',
              order.deliveryFee != null
                  ? formatPeso(order.deliveryFee!)
                  : 'To be arranged with $feeParty',
            ),
            if (order.buyerAddress.isNotEmpty)
              _line('Deliver to', order.buyerAddress),
            if (order.isLongDistance)
              _note(
                'Long-distance delivery, outside the standard coverage — '
                'arranged between buyer and farmer in Messages.',
              ),
          ],
          if (order.isPickup)
            // Only the farmer's general area is ever shown; the exact
            // pick-up point is agreed in Messages.
            FutureBuilder<Map<String, dynamic>>(
              future: _role == OrderRole.buyer ? _otherProfile : null,
              builder: (context, snapshot) {
                final area = _area(snapshot.data ?? const {});
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (area.isNotEmpty) _line('Pick-up area', area),
                    _note(
                      'Arrange the exact pick-up point and time in Messages.',
                    ),
                  ],
                );
              },
            ),
          if (order.neededBy != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _line(
                'Requested date',
                MaterialLocalizations.of(
                  context,
                ).formatMediumDate(order.neededBy!),
              ),
            ),
          if (order.confirmedFulfillmentDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _line(
                'Confirmed date',
                MaterialLocalizations.of(
                  context,
                ).formatMediumDate(order.confirmedFulfillmentDate!),
              ),
            ),
          if (order.status == 'shipped')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                order.shippedProgressLabel,
                style: GoogleFonts.montserrat(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: orderStatusColor('shipped'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _payment(OrderInfo order) {
    final total = order.grandTotal;
    final feeParty = _role == OrderRole.farmer ? 'buyer' : 'seller';
    return _section(
      title: 'Payment Summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _line('Subtotal', formatPeso(order.subtotal)),
          if (order.isDelivery)
            _line(
              'Delivery fee',
              order.deliveryFee != null
                  ? formatPeso(order.deliveryFee!)
                  : 'To be arranged with $feeParty',
            ),
          Divider(height: 14, color: Colors.grey.shade200),
          if (total != null)
            _line(
              'Total',
              formatPeso(total),
              strong: true,
              color: AppTheme.dark,
            )
          else ...[
            _line(
              'Product total',
              formatPeso(order.subtotal),
              strong: true,
              color: AppTheme.dark,
            ),
            _note(
              'The delivery fee is not included — it is arranged directly '
              'with the $feeParty, so the final amount is not shown here.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _receipt(OrderInfo order) => _section(
    title: 'Transaction Receipt',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              color: AppTheme.dark,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _note(
                'A receipt was issued for this completed transaction. Both '
                'the farmer and the buyer can open it.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OrderActionButton(
              OrderCardAction(
                'View Receipt',
                () => OrderActions.viewReceipt(context, order.id),
              ),
            ),
            if (_role == OrderRole.farmer)
              OrderActionButton(
                OrderCardAction(
                  'Send to Buyer in Messages',
                  () => OrderActions.message(
                    context,
                    order,
                    _role,
                    withReceipt: true,
                  ),
                ),
              ),
            if (_role == OrderRole.buyer)
              order.reviewed
                  ? Chip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: const Color(0xFFEFF6E8),
                      side: BorderSide.none,
                      avatar: const Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: Colors.amber,
                      ),
                      label: Text(
                        'You reviewed this product',
                        style: GoogleFonts.montserrat(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.dark,
                        ),
                      ),
                    )
                  : OrderActionButton(
                      OrderCardAction(
                        'Review Product',
                        () => OrderActions.review(context, order),
                      ),
                    ),
          ],
        ),
      ],
    ),
  );

  Widget _timeline(OrderInfo order) {
    // (label, reached, when). A stage with no stored time is still shown
    // as reached when a later status proves it happened — but never with
    // an invented time, and unreached stages stay unticked.
    final List<(String, bool, DateTime?)> stages;
    if (order.isCancelled) {
      stages = [
        ('Order Placed', true, order.createdAt),
        ('Cancelled by buyer', true, order.cancelledAt ?? order.updatedAt),
      ];
    } else if (order.status == 'rejected') {
      stages = [
        ('Order Placed', true, order.createdAt),
        ('Rejected', true, order.rejectedAt ?? order.updatedAt),
      ];
    } else {
      final rank = const [
        'pending',
        'confirmed',
        'shipped',
        'completed',
      ].indexOf(order.status);
      DateTime? at(int stage, DateTime? stored) =>
          stored ?? (rank == stage ? order.updatedAt : null);
      stages = [
        ('Order Placed', true, order.createdAt),
        ('Confirmed', rank >= 1, at(1, order.confirmedAt)),
        (
          order.isPickup ? 'Ready for Pick-up' : 'Shipped',
          rank >= 2,
          at(2, order.shippedAt),
        ),
        ('Completed', rank >= 3, at(3, order.completedAt)),
      ];
    }

    return _section(
      title: 'Order Timeline',
      child: Column(
        children: [
          for (var i = 0; i < stages.length; i++)
            _timelineRow(
              stages[i],
              isLast: i == stages.length - 1,
              rejected:
                  (order.status == 'rejected' || order.isCancelled) && i == 1,
            ),
        ],
      ),
    );
  }

  Widget _timelineRow(
    (String, bool, DateTime?) stage, {
    required bool isLast,
    bool rejected = false,
  }) {
    final (label, reached, at) = stage;
    final color = rejected
        ? Colors.red.shade700
        : reached
        ? AppTheme.dark
        : Colors.grey.shade400;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Icon(
                reached
                    ? (rejected ? Icons.cancel : Icons.check_circle)
                    : Icons.radio_button_unchecked,
                size: 18,
                color: color,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: Colors.grey.shade300,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      fontWeight: reached ? FontWeight.w600 : FontWeight.w500,
                      color: reached ? Colors.black87 : Colors.grey[500],
                    ),
                  ),
                  if (reached)
                    _note(
                      at == null
                          ? 'Time not recorded'
                          : formatOrderDateTimeLong(at),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBar(List<OrderCardAction> actions) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Colors.grey.shade200)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: OrderActionButton(actions[i], large: true)),
            ],
          ],
        ),
      ),
    ),
  );
}
