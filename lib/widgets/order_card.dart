import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/market_price_helpers.dart';
import '../services/order_format.dart';
import '../theme/app_theme.dart';

enum OrderActionKind { primary, secondary, destructive, text }

/// One compact button on an order card or the order details screen.
class OrderCardAction {
  final String label;
  final VoidCallback onTap;
  final OrderActionKind kind;

  const OrderCardAction(
    this.label,
    this.onTap, {
    this.kind = OrderActionKind.secondary,
  });
}

Color orderStatusColor(String status) => switch (status) {
  'confirmed' => AppTheme.mid,
  'shipped' => const Color(0xFF1565C0),
  'completed' => AppTheme.dark,
  'rejected' || 'cancelled' => Colors.red.shade700,
  'delayed' => Colors.orange.shade800,
  _ => const Color(0xFFB8860B), // pending
};

/// Small uppercase status tag (PENDING, CONFIRMED, ...).
class OrderStatusTag extends StatelessWidget {
  final String status;

  const OrderStatusTag(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = orderStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.montserrat(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Small RETAIL / WHOLESALE tag.
class OrderPricingTag extends StatelessWidget {
  final OrderInfo order;

  const OrderPricingTag(this.order, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: order.isWholesale ? const Color(0xFFEFF6E8) : Colors.grey[100],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        order.pricingLabel,
        style: GoogleFonts.montserrat(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: order.isWholesale ? AppTheme.dark : Colors.grey[700],
        ),
      ),
    );
  }
}

/// Product photo square with an initial-letter fallback.
class OrderThumbnail extends StatelessWidget {
  final OrderInfo order;
  final double size;

  const OrderThumbnail(this.order, {super.key, this.size = 60});

  @override
  Widget build(BuildContext context) {
    final name = order.productName;
    final fallback = Container(
      color: AppTheme.accent,
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.bold,
          color: AppTheme.dark,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: order.imageUrl.isEmpty
            ? fallback
            : Image.network(
                order.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

/// A compact button sized for order cards.
class OrderActionButton extends StatelessWidget {
  final OrderCardAction action;

  /// Larger hit area and text, for the details screen's bottom bar.
  final bool large;

  const OrderActionButton(this.action, {super.key, this.large = false});

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, BorderSide side) = switch (action.kind) {
      OrderActionKind.primary => (Colors.white, AppTheme.dark, BorderSide.none),
      OrderActionKind.secondary => (
        AppTheme.dark,
        Colors.white,
        BorderSide(color: Colors.grey.shade400),
      ),
      OrderActionKind.destructive => (
        Colors.red.shade700,
        Colors.white,
        BorderSide(color: Colors.red.shade200),
      ),
      OrderActionKind.text => (
        AppTheme.dark,
        Colors.transparent,
        BorderSide.none,
      ),
    };
    final height = large ? 42.0 : 30.0;
    return TextButton(
      onPressed: action.onTap,
      style: TextButton.styleFrom(
        foregroundColor: fg,
        backgroundColor: bg,
        side: side,
        minimumSize: Size(0, height),
        fixedSize: Size.fromHeight(height),
        padding: EdgeInsets.symmetric(
          horizontal: action.kind == OrderActionKind.text
              ? 6
              : (large ? 16 : 10),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: GoogleFonts.montserrat(
          fontSize: large ? 13 : 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(action.label, maxLines: 1),
    );
  }
}

/// The compact order card shared by the Farmer and Buyer Orders screens.
/// The layout is identical for both; [role] only decides whose name is
/// shown, and the caller passes the actions that role may take.
class OrderCard extends StatelessWidget {
  final OrderInfo order;
  final OrderRole role;

  /// Has activity this user hasn't seen yet — shows a small red dot.
  final bool isNew;
  final VoidCallback onDetails;
  final VoidCallback? onMessage;
  final List<OrderCardAction> actions;

  const OrderCard({
    super.key,
    required this.order,
    required this.role,
    required this.onDetails,
    this.isNew = false,
    this.onMessage,
    this.actions = const [],
  });

  TextStyle _muted([double size = 11.5]) =>
      GoogleFonts.montserrat(fontSize: size, color: Colors.grey[600]);

  String get _dateLine {
    if (order.isCompleted && order.completedAt != null) {
      return 'Completed ${formatOrderDateTime(order.completedAt!)}';
    }
    final created = order.createdAt;
    return created == null ? '' : 'Ordered ${formatOrderDateTime(created)}';
  }

  @override
  Widget build(BuildContext context) {
    final total = order.grandTotal;
    final partyLine = [
      order.otherPartyName(role),
      if (order.fulfillmentLabel.isNotEmpty) order.fulfillmentLabel,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onDetails,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OrderThumbnail(order),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  order.productName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.montserrat(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              if (isNew)
                                Container(
                                  key: const ValueKey('order-new-dot'),
                                  margin: const EdgeInsets.only(left: 6),
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE53935),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              const Spacer(),
                              const SizedBox(width: 6),
                              // A confirmed order waiting on a new date reads
                              // DELAYED; its real status is still confirmed.
                              OrderStatusTag(
                                order.isDelayed ? 'delayed' : order.status,
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Wrap(
                            spacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                order.quantityLabel,
                                style: GoogleFonts.montserrat(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                              ),
                              OrderPricingTag(order),
                              if (order.unitPriceLabel.isNotEmpty)
                                Text(order.unitPriceLabel, style: _muted(11)),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            partyLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _muted(),
                          ),
                          if (_dateLine.isNotEmpty)
                            Text(_dateLine, style: _muted(10.5)),
                          if (order.status == 'shipped')
                            Text(
                              order.shippedProgressLabel,
                              style: GoogleFonts.montserrat(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: orderStatusColor('shipped'),
                              ),
                            ),
                          // Delayed: why, and the date being proposed.
                          if (order.isDelayed)
                            Text(
                              [
                                order.delayReasonLabel,
                                if (order.delayProposedDate != null)
                                  'new date ${MaterialLocalizations.of(context).formatMediumDate(order.delayProposedDate!)}',
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.montserrat(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange[800],
                              ),
                            )
                          else if (order.confirmedFulfillmentDate != null &&
                              (order.status == 'confirmed' ||
                                  order.status == 'shipped'))
                            Text(
                              'Rescheduled to ${MaterialLocalizations.of(context).formatMediumDate(order.confirmedFulfillmentDate!)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.montserrat(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.dark,
                              ),
                            )
                          // The buyer's preferred date — a request, shown
                          // while the farmer is still deciding.
                          else if (order.status == 'pending' &&
                              order.neededBy != null)
                            Text(
                              'Requested for ${MaterialLocalizations.of(context).formatMediumDate(order.neededBy!)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.montserrat(
                                fontSize: 10.5,
                                color: Colors.orange[800],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Divider(height: 1, color: Colors.grey.shade200),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          total == null ? 'Subtotal + delivery' : 'Total',
                          style: _muted(10),
                        ),
                        Text(
                          formatPeso(total ?? order.subtotal),
                          style: GoogleFonts.montserrat(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.dark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (onMessage != null)
                            SizedBox(
                              width: 30,
                              height: 30,
                              child: IconButton(
                                onPressed: onMessage,
                                tooltip: role == OrderRole.farmer
                                    ? 'Message Buyer'
                                    : 'Message Farmer',
                                padding: EdgeInsets.zero,
                                iconSize: 17,
                                color: AppTheme.dark,
                                style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  side: BorderSide(color: Colors.grey.shade400),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: const Icon(Icons.chat_bubble_outline),
                              ),
                            ),
                          OrderActionButton(
                            OrderCardAction(
                              'Details',
                              onDetails,
                              kind: OrderActionKind.text,
                            ),
                          ),
                          for (final action in actions)
                            OrderActionButton(action),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
