import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/order_contact_service.dart';
import '../services/support_request_service.dart';
import '../theme/app_theme.dart';
import 'agri_dialog.dart';

/// What Order Details shows about phone contact, for one side of an order.
///
/// While the order is pending: only a line saying numbers are shared once
/// the farmer confirms. While it is confirmed or on its way: the other
/// side's number for this order, with Call, Copy and a way to report a
/// wrong number. For any other status the caller does not show this at
/// all (see [OrderContactService.isShared]).
///
/// Messages stays the main channel — the number is offered as a fallback,
/// and is never a claim that it was verified.
class OrderContactSection extends StatefulWidget {
  final String orderId;
  final String status;
  final bool viewerIsFarmer;

  /// The buyer's number as older orders stored it, on the order itself.
  final String? legacyBuyerContact;

  /// For tests: stands in for the Firestore lookup.
  final Future<String> Function()? loadContact;

  /// For tests: stands in for filing the support request. Returns an error
  /// message, or null when sent.
  final Future<String?> Function(String subject, String message)? sendReport;

  const OrderContactSection({
    super.key,
    required this.orderId,
    required this.status,
    required this.viewerIsFarmer,
    this.legacyBuyerContact,
    this.loadContact,
    this.sendReport,
  });

  @override
  State<OrderContactSection> createState() => _OrderContactSectionState();
}

class _OrderContactSectionState extends State<OrderContactSection> {
  Future<String>? _contact;
  bool _reporting = false;
  bool _reported = false;

  bool get _shared => OrderContactService.isShared(widget.status);
  String get _other => widget.viewerIsFarmer ? 'buyer' : 'farmer';

  @override
  void initState() {
    super.initState();
    if (_shared) _contact = _load();
  }

  @override
  void didUpdateWidget(OrderContactSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The order was just confirmed while this screen was open.
    if (_shared && _contact == null) _contact = _load();
  }

  Future<String> _load() =>
      widget.loadContact?.call() ??
      OrderContactService.instance.otherPartyContact(
        orderId: widget.orderId,
        viewerIsFarmer: widget.viewerIsFarmer,
        legacyBuyerContact: widget.legacyBuyerContact,
      );

  TextStyle _text({
    double size = 12,
    Color? color,
    FontWeight weight = FontWeight.w400,
  }) => GoogleFonts.montserrat(
    fontSize: size,
    color: color ?? Colors.grey[600],
    fontWeight: weight,
    height: 1.4,
  );

  void _say(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _call(String number) async {
    final opened = await launchUrl(Uri(scheme: 'tel', path: number));
    if (!opened && mounted) _say('Could not open the phone app.');
  }

  Future<void> _copy(String number) async {
    await Clipboard.setData(ClipboardData(text: number));
    if (mounted) _say('Number copied.');
  }

  Future<void> _report() async {
    final confirmed = await showAgriConfirm(
      context: context,
      icon: Icons.phone_disabled_outlined,
      tone: AgriTone.warning,
      title: 'Report incorrect number?',
      message:
          "This tells AgriTrade+ support that the $_other's contact number "
          'on this order is wrong or cannot be reached. You can keep using '
          'Messages to reach them.',
      confirmLabel: 'Report',
    );
    if (!confirmed || !mounted) return;

    setState(() => _reporting = true);
    // The number itself is left out: support looks it up from the order.
    final subject = 'Incorrect contact number on order ${widget.orderId}';
    final message =
        "The $_other's contact number on order ${widget.orderId} is "
        'incorrect or cannot be reached. Reported by the '
        '${widget.viewerIsFarmer ? 'farmer' : 'buyer'} on this order.';
    final error =
        await (widget.sendReport?.call(subject, message) ??
            SupportRequestService().submit(subject: subject, message: message));
    if (!mounted) return;
    setState(() {
      _reporting = false;
      _reported = error == null;
    });
    _say(error ?? 'Reported. Our support team will look into it.');
  }

  @override
  Widget build(BuildContext context) {
    if (!_shared) {
      return Text(
        'Contact numbers are shared once the farmer confirms this order. '
        'Until then, use Messages.',
        style: _text(),
      );
    }

    return FutureBuilder<String>(
      future: _contact,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.mid,
            ),
          );
        }
        final number = snapshot.data ?? '';
        if (number.isEmpty) {
          return Text(
            'The $_other has no contact number on this order. '
            'Use Messages to reach them.',
            style: _text(),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.phone_outlined, size: 18, color: AppTheme.mid),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    number,
                    style: _text(
                      size: 14.5,
                      color: Colors.black87,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy number',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  color: Colors.grey[700],
                  onPressed: () => _copy(number),
                ),
                IconButton(
                  tooltip: 'Call',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.call_rounded, size: 20),
                  color: AppTheme.mid,
                  onPressed: () => _call(number),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'For this order only. Messages is still the best way to '
              'reach the $_other; call or text only if you need to.',
              style: _text(size: 11.5),
            ),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _reporting || _reported ? null : _report,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _reported ? 'Reported to support' : 'Report incorrect number',
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
