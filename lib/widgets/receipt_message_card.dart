import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screen/order_actions.dart';
import '../services/market_price_helpers.dart';
import '../services/order_format.dart';
import '../theme/app_theme.dart';
import 'order_card.dart';

/// The receipt of a completed order, as it appears in the farmer–buyer
/// conversation (a message of type 'receipt'). Both sides get View Receipt;
/// the buyer of that order also gets Review Product.
///
/// What it shows and allows comes from the order itself, read live — the
/// message only says which order it is for.
class ReceiptMessageCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool isMe;

  const ReceiptMessageCard({super.key, required this.data, required this.isMe});

  @override
  State<ReceiptMessageCard> createState() => _ReceiptMessageCardState();
}

class _ReceiptMessageCardState extends State<ReceiptMessageCard> {
  late final String _orderId = (widget.data['orderId'] ?? '').toString();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>? _orderStream =
      _orderId.isEmpty
      ? null
      : FirebaseFirestore.instance
            .collection('orders')
            .doc(_orderId)
            .snapshots();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _orderStream,
          builder: (context, snapshot) {
            final order = snapshot.data?.exists == true
                ? OrderInfo.fromDoc(snapshot.data!)
                : null;
            return _content(context, order);
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, OrderInfo? order) {
    final data = widget.data;
    final displayId =
        order?.displayId ?? (data['orderDisplayId'] ?? '').toString();
    // No figure when the delivery fee was arranged outside the order.
    final total = order != null ? order.grandTotal : data['total'] as num?;
    final subtotal = order?.subtotal ?? (data['subtotal'] as num?) ?? 0;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isBuyer = order != null && uid != null && uid == order.buyerId;
    final available = order?.isCompleted ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              color: AppTheme.dark,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Transaction Receipt',
                style: GoogleFonts.montserrat(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.dark,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'PDF',
                style: GoogleFonts.montserrat(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.red.shade700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (displayId.isNotEmpty)
          Text(
            'Order #$displayId',
            style: GoogleFonts.montserrat(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        if ((order?.productName ?? data['productName'] ?? '')
            .toString()
            .isNotEmpty)
          Text(
            (order?.productName ?? data['productName']).toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.montserrat(
              fontSize: 11.5,
              color: Colors.grey[600],
            ),
          ),
        const SizedBox(height: 6),
        const OrderStatusTag('completed'),
        const SizedBox(height: 6),
        Text(
          total != null
              ? 'Total: ${formatPeso(total)}'
              : 'Total: ${formatPeso(subtotal)} + delivery fee',
          style: GoogleFonts.montserrat(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            OrderActionButton(
              OrderCardAction(
                'View Receipt',
                () => OrderActions.viewReceipt(context, _orderId),
                kind: OrderActionKind.primary,
              ),
            ),
            if (isBuyer && available && !order.reviewed)
              OrderActionButton(
                OrderCardAction(
                  'Review Product',
                  () => OrderActions.review(context, order),
                ),
              ),
            if (isBuyer && order.reviewed)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(
                  'Reviewed',
                  style: GoogleFonts.montserrat(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.dark,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
