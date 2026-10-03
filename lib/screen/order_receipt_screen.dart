import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../services/download_helper.dart';
import '../services/order_receipt_service.dart';
import '../theme/app_theme.dart';
import '../widgets/retry_message.dart';

/// Shows the formal PDF Transaction Receipt of a completed order. Farmer
/// and buyer open the same document; it is read-only, and can be shared,
/// printed or saved as `AgriTrade_Receipt_<OrderID>.pdf`.
class OrderReceiptScreen extends StatefulWidget {
  final String orderId;

  const OrderReceiptScreen({super.key, required this.orderId});

  @override
  State<OrderReceiptScreen> createState() => _OrderReceiptScreenState();
}

class _OrderReceiptScreenState extends State<OrderReceiptScreen> {
  late Future<(OrderReceipt, Uint8List)?> _receipt = _load();

  Future<(OrderReceipt, Uint8List)?> _load() async {
    final receipt = await OrderReceiptService().load(widget.orderId);
    if (receipt == null) return null;
    return (receipt, await OrderReceiptService.buildPdf(receipt));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F5),
      appBar: AppBar(
        title: const Text('Transaction Receipt'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.dark,
        elevation: 0,
        titleTextStyle: AppTheme.heading(17).copyWith(color: AppTheme.dark),
      ),
      body: FutureBuilder<(OrderReceipt, Uint8List)?>(
        future: _receipt,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.dark,
                ),
              ),
            );
          }
          if (snapshot.hasError) {
            return RetryMessage(
              message:
                  'Could not load this receipt. Check your connection and try again.',
              onRetry: () => setState(() => _receipt = _load()),
            );
          }
          final loaded = snapshot.data;
          if (loaded == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'A receipt is available once the order is completed.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final (receipt, bytes) = loaded;
          return PdfPreview(
            build: (_) => bytes,
            initialPageFormat: PdfPageFormat.a4,
            pdfFileName: receipt.fileName,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            actionBarTheme: const PdfActionBarTheme(
              backgroundColor: AppTheme.dark,
            ),
            actions: [
              PdfPreviewAction(
                icon: const Icon(Icons.download_outlined),
                onPressed: (context, build, format) =>
                    WebDownloadHelper.download(
                      bytes,
                      receipt.fileName,
                      'application/pdf',
                    ),
              ),
            ],
          );
        },
      ),
    );
  }
}
