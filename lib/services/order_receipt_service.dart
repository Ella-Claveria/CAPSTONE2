import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'order_format.dart';

/// The Transaction Receipt of one completed order.
///
/// [order] is the frozen transaction record: the snapshot the
/// issueOrderReceipt Cloud Function stored in `receipts/{orderId}` when the
/// order was completed, or — for orders completed before that existed — the
/// completed order document itself, which neither side can edit any more
/// (see firestore.rules). It is never rebuilt from the product listing, so
/// later price or stock changes can't alter an issued receipt.
class OrderReceipt {
  final OrderInfo order;
  final String receiptNumber;
  final DateTime? generatedAt;

  /// The farmer's general area ("Barangay, Municipality"), never an exact
  /// address or pin.
  final String sellerArea;

  const OrderReceipt({
    required this.order,
    required this.receiptNumber,
    required this.generatedAt,
    required this.sellerArea,
  });

  String get fileName => 'AgriTrade_Receipt_${order.displayId}.pdf';
}

class OrderReceiptService {
  static const _brandGreen = PdfColor.fromInt(0xFF0E3210);
  static const _softGreen = PdfColor.fromInt(0xFFEFF6E8);
  static final _money = NumberFormat('#,##0.00');
  static final _date = DateFormat("MMM d, y 'at' h:mm a");

  final _db = FirebaseFirestore.instance;

  /// The receipt for [orderId], or null if that order isn't completed (or
  /// isn't this user's to read).
  Future<OrderReceipt?> load(String orderId) async {
    try {
      final issued = await _db.collection('receipts').doc(orderId).get();
      final data = issued.data();
      if (data != null) {
        final generatedAt = data['generatedAt'];
        return OrderReceipt(
          order: OrderInfo(orderId, data),
          receiptNumber: (data['receiptNumber'] ?? '').toString(),
          generatedAt: generatedAt is Timestamp ? generatedAt.toDate() : null,
          sellerArea: (data['sellerArea'] ?? '').toString(),
        );
      }
    } catch (_) {
      // Not issued yet (or not readable) — fall back to the order itself.
    }

    final snap = await _db.collection('orders').doc(orderId).get();
    if (!snap.exists) return null;
    final order = OrderInfo.fromDoc(snap);
    if (!order.isCompleted) return null;
    return OrderReceipt(
      order: order,
      receiptNumber: receiptNumberFor(order.id, order.createdAt),
      generatedAt: order.completedAt ?? order.updatedAt,
      sellerArea: await generalAreaOf(order.sellerId),
    );
  }

  /// "Barangay, Municipality" from a user's public profile ('' if unset).
  Future<String> generalAreaOf(String uid) async {
    if (uid.isEmpty) return '';
    try {
      final profile =
          (await _db.collection('publicProfiles').doc(uid).get()).data() ??
          const {};
      return [profile['barangay'], profile['municipality']]
          .map((v) => (v ?? '').toString().trim())
          .where((v) => v.isNotEmpty)
          .join(', ');
    } catch (_) {
      return '';
    }
  }

  static String _peso(num value) => 'PHP ${_money.format(value)}';
  static String _when(DateTime? date) =>
      date == null ? 'Not recorded' : _date.format(date);

  static String _quantity(num quantity) => quantity == quantity.roundToDouble()
      ? quantity.toStringAsFixed(0)
      : quantity.toStringAsFixed(2);

  /// The formal A4 receipt. Deterministic for a given [receipt], so the
  /// farmer and the buyer always open the same document.
  static Future<Uint8List> buildPdf(OrderReceipt receipt) async {
    final order = receipt.order;

    // Montserrat to match the app. If it can't be fetched (offline, first
    // use) the printing package hands back the built-in Helvetica, which
    // only covers Latin-1 — so anything outside it is replaced rather than
    // failing the whole receipt.
    pw.ThemeData? theme;
    var latinOnly = true;
    try {
      final base = await PdfGoogleFonts.montserratRegular();
      final semiBold = await PdfGoogleFonts.montserratSemiBold();
      latinOnly = base is! pw.TtfFont || semiBold is! pw.TtfFont;
      theme = pw.ThemeData.withFont(base: base, bold: semiBold);
    } catch (_) {}
    String safe(String text) => latinOnly
        ? String.fromCharCodes(text.runes.map((r) => r > 0xFF ? 0x3F : r))
        : text;

    pw.ImageProvider? logo;
    try {
      final bytes = await rootBundle.load('assets/images/logo.png');
      logo = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {}

    final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
    const muted = pw.TextStyle(fontSize: 9, color: PdfColors.grey700);

    pw.Widget sectionTitle(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
      child: pw.Text(
        text.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: _brandGreen,
          letterSpacing: 0.8,
        ),
      ),
    );

    pw.Widget labelled(String label, String value, {bool strong = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(width: 130, child: pw.Text(label, style: muted)),
              pw.Expanded(
                child: pw.Text(
                  value,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: strong ? pw.FontWeight.bold : null,
                  ),
                ),
              ),
            ],
          ),
        );

    pw.Widget party(String title, String name, String detail) => pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: muted),
            pw.SizedBox(height: 3),
            pw.Text(name, style: bold.copyWith(fontSize: 11)),
            if (detail.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text(detail, style: muted),
            ],
          ],
        ),
      ),
    );

    pw.Widget amountRow(String label, String value, {bool total = false}) =>
        pw.Container(
          color: total ? _softGreen : null,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  label,
                  style: pw.TextStyle(
                    fontSize: total ? 11 : 10,
                    fontWeight: total ? pw.FontWeight.bold : null,
                    color: total ? _brandGreen : null,
                  ),
                ),
              ),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: total ? 12 : 10,
                  fontWeight: total ? pw.FontWeight.bold : null,
                  color: total ? _brandGreen : null,
                ),
              ),
            ],
          ),
        );

    final deliveryFeeText = !order.isDelivery
        ? 'None'
        : order.deliveryFee != null
        ? _peso(order.deliveryFee!)
        : 'Arranged directly with seller (not recorded)';
    final total = order.grandTotal;

    final doc = pw.Document(
      theme: theme,
      title: 'Transaction Receipt ${receipt.receiptNumber}',
      author: 'AgriTrade+',
    );
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(44),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null) ...[
                  pw.Image(logo, width: 38, height: 38),
                  pw.SizedBox(width: 10),
                ],
                pw.Text(
                  'AgriTrade+',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: _brandGreen,
                  ),
                ),
                pw.Spacer(),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Transaction Receipt',
                      style: bold.copyWith(fontSize: 15),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(receipt.receiptNumber, style: muted),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Container(height: 2, color: _brandGreen),
            pw.SizedBox(height: 12),

            labelled('Receipt Number', receipt.receiptNumber, strong: true),
            labelled('Order ID', order.displayId),
            labelled('Transaction Status', 'COMPLETED', strong: true),
            labelled('Date Generated', _when(receipt.generatedAt)),
            labelled('Order Date', _when(order.createdAt)),
            labelled('Completion Date', _when(order.completedAt)),

            sectionTitle('Parties'),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                party(
                  'Seller / Farmer',
                  safe(order.sellerName),
                  safe(receipt.sellerArea),
                ),
                pw.SizedBox(width: 12),
                party('Buyer', safe(order.buyerName), ''),
              ],
            ),

            sectionTitle('Order Details'),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Product',
                'Type',
                'Quantity',
                'Unit',
                'Unit Price',
                'Subtotal',
              ],
              data: [
                [
                  safe(order.productName),
                  order.isWholesale ? 'Wholesale' : 'Retail',
                  _quantity(order.quantity),
                  order.unit.isEmpty ? '-' : safe(order.unit),
                  order.unitPrice == null ? '-' : _peso(order.unitPrice!),
                  _peso(order.subtotal),
                ],
              ],
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(color: _brandGreen),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 7,
              ),
              cellAlignments: const {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerLeft,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
              },
              columnWidths: const {
                0: pw.FlexColumnWidth(2.6),
                1: pw.FlexColumnWidth(1.4),
                2: pw.FlexColumnWidth(1.2),
                3: pw.FlexColumnWidth(1.3),
                4: pw.FlexColumnWidth(1.8),
                5: pw.FlexColumnWidth(1.8),
              },
              border: null,
              rowDecoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                ),
              ),
            ),

            sectionTitle('Fulfillment'),
            labelled(
              'Method',
              order.fulfillmentLabel.isEmpty
                  ? 'Not specified'
                  : order.fulfillmentLabel,
            ),
            if (order.isDelivery) labelled('Delivery Fee', deliveryFeeText),

            sectionTitle('Payment Summary'),
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
              ),
              child: pw.Column(
                children: [
                  amountRow('Subtotal', _peso(order.subtotal)),
                  amountRow(
                    'Delivery Fee',
                    order.deliveryFee != null
                        ? _peso(order.deliveryFee!)
                        : order.isDelivery
                        ? 'Not recorded'
                        : _peso(0),
                  ),
                  amountRow(
                    total == null
                        ? 'Total Transaction Amount (excluding delivery fee)'
                        : 'Total Transaction Amount',
                    _peso(total ?? order.subtotal),
                    total: true,
                  ),
                ],
              ),
            ),

            pw.Spacer(),
            pw.Divider(color: PdfColors.grey300, height: 16),
            pw.Text(
              'This receipt was generated by AgriTrade+ from the completed '
              'transaction record.',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              'Transaction reference: ${order.id}  |  This is a record of a '
              'marketplace transaction and is not an official tax invoice.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }
}
