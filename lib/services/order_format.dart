import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'market_price_helpers.dart';

/// Which side of an order the signed-in user is on. The Orders screens,
/// cards, details and receipt are shared; only the wording and the actions
/// change with this.
enum OrderRole { farmer, buyer }

/// Short, human-readable code for an order document id, shared by the
/// order reference and the receipt number. The year uses Philippine time
/// so the app and the Cloud Function (see issueOrderReceipt) always agree.
String _orderCode(String orderId, DateTime? createdAt) {
  final clean = orderId.replaceAll(RegExp('[^A-Za-z0-9]'), '');
  final code = (clean.length > 6 ? clean.substring(0, 6) : clean).toUpperCase();
  final year = (createdAt ?? DateTime.now())
      .toUtc()
      .add(const Duration(hours: 8))
      .year;
  return '$year-$code';
}

/// "AGR-2026-K3F9QZ" — the order reference shown to both parties.
String orderDisplayId(String orderId, DateTime? createdAt) =>
    'AGR-${_orderCode(orderId, createdAt)}';

/// "RCT-2026-K3F9QZ" — the receipt number of a completed order.
String receiptNumberFor(String orderId, DateTime? createdAt) =>
    'RCT-${_orderCode(orderId, createdAt)}';

/// "Sep 27 · 4:28 PM"
String formatOrderDateTime(DateTime date) =>
    '${DateFormat('MMM d').format(date)} · ${DateFormat('h:mm a').format(date)}';

/// "Sep 27, 2026 · 4:28 PM"
String formatOrderDateTimeLong(DateTime date) =>
    '${DateFormat('MMM d, y').format(date)} · ${DateFormat('h:mm a').format(date)}';

/// Why a confirmed order is being delayed — the values stored in
/// orders/{id}.delay.reason, and what the app shows for each.
const Map<String, String> kOrderDelayReasons = {
  'weather': 'Weather / Natural Disaster',
  'transport': 'Road or Transportation Issue',
  'supply': 'Harvest / Supply Delay',
  'other': 'Other',
};

String orderDelayReasonLabel(String reason) =>
    kOrderDelayReasons[reason] ?? 'Delay';

/// Read-only view of one `orders/{id}` document. Every value comes from the
/// order as it was stored when placed — never from the current product
/// listing — so prices and totals stay those of the transaction.
class OrderInfo {
  final String id;
  final Map<String, dynamic> data;

  const OrderInfo(this.id, this.data);

  factory OrderInfo.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      OrderInfo(doc.id, doc.data() ?? const {});

  String _text(String key) => (data[key] ?? '').toString().trim();
  DateTime? _date(String key) {
    final value = data[key];
    return value is Timestamp ? value.toDate() : null;
  }

  num? _num(String key) {
    final value = data[key];
    return value is num ? value : num.tryParse('${value ?? ''}');
  }

  String get status {
    final value = _text('status').toLowerCase();
    return value.isEmpty ? 'pending' : value;
  }

  bool get isCompleted => status == 'completed';

  String get productId => _text('productId');
  String get productName {
    final name = _text('productName');
    return name.isNotEmpty
        ? name
        : (_text('name').isNotEmpty ? _text('name') : 'Product');
  }

  String get imageUrl => _text('imageUrl');
  String get unit => _text('unit');
  num get quantity => _num('quantity') ?? 0;
  String get quantityLabel {
    final label = _text('quantityLabel');
    return label.isNotEmpty ? label : '${data['quantity'] ?? ''} $unit'.trim();
  }

  bool get isWholesale => _text('pricingType').toLowerCase() == 'wholesale';
  String get pricingLabel => isWholesale ? 'WHOLESALE' : 'RETAIL';
  num? get unitPrice => _num('pricePerUnit') ?? _num('unitPrice');
  String get unitPriceLabel =>
      unitPrice == null ? '' : formatPriceWithUnit(unitPrice!, unit);

  /// Product subtotal (quantity × unit price), without any delivery fee.
  num get subtotal => _num('subtotal') ?? _num('total') ?? 0;

  String get sellerId => _text('sellerId');
  String get buyerId => _text('buyerId');
  String get sellerName =>
      _text('sellerName').isEmpty ? 'Farmer' : _text('sellerName');
  String get buyerName =>
      _text('buyerName').isEmpty ? 'Buyer' : _text('buyerName');
  String get buyerAddress => _text('buyerAddress');

  String otherPartyName(OrderRole role) =>
      role == OrderRole.farmer ? buyerName : sellerName;
  String otherPartyId(OrderRole role) =>
      role == OrderRole.farmer ? buyerId : sellerId;

  bool get isDelivery => _text('deliveryMethod').toLowerCase() == 'delivery';
  bool get isPickup => _text('deliveryMethod').toLowerCase() == 'pickup';

  /// "Delivery", "Pick-up", or '' for older orders with no method stored.
  String get fulfillmentLabel => isDelivery
      ? 'Delivery'
      : isPickup
      ? 'Pick-up'
      : '';
  bool get isLongDistance => _text('deliveryArrangement') == 'longDistance';

  /// The fixed delivery fee, or null when there is none on record (pick-up,
  /// or a delivery whose fee the two sides arrange between themselves).
  num? get deliveryFee => isDelivery ? _num('deliveryFee') : null;

  /// A delivery whose fee was left to be arranged, so no figure is stored.
  bool get feeArranged => isDelivery && deliveryFee == null;

  /// What the buyer pays in total, or null when it can't be known because
  /// the delivery fee was arranged outside the order.
  num? get grandTotal {
    if (feeArranged) return null;
    return _num('grandTotal') ?? subtotal + (deliveryFee ?? 0);
  }

  DateTime? get createdAt => _date('createdAt');
  DateTime? get updatedAt => _date('updatedAt');
  DateTime? get confirmedAt => _date('confirmedAt');
  DateTime? get shippedAt => _date('shippedAt');
  DateTime? get completedAt => _date('completedAt');
  DateTime? get rejectedAt => _date('rejectedAt');

  /// The date the buyer asked for when ordering — a preference, not a
  /// promise: the farmer decides whether it can be met, and nothing happens
  /// automatically when it passes. Stored as requestedFulfillmentDate
  /// ('neededBy' on orders placed before that name existed).
  DateTime? get neededBy =>
      _date('requestedFulfillmentDate') ?? _date('neededBy');

  /// The date both sides have agreed on, once a proposed new date has been
  /// accepted by the buyer.
  DateTime? get confirmedFulfillmentDate => _date('confirmedFulfillmentDate');

  bool get isCancelled => status == 'cancelled';
  DateTime? get cancelledAt => _date('cancelledAt');

  // ---- Delay / reschedule (a confirmed order only) ----
  // The farmer reports a delay with a reason and a proposed new date; the
  // order keeps its id, status ('confirmed'), stock and prices. The buyer
  // then accepts the date, cancels, or messages the farmer.
  Map<String, dynamic> get _delay {
    final value = data['delay'];
    return value is Map ? Map<String, dynamic>.from(value) : const {};
  }

  /// Waiting for the buyer to answer a proposed new date.
  bool get isDelayed => status == 'confirmed' && _delay['status'] == 'proposed';

  /// The buyer accepted the proposed date.
  bool get delayAccepted => _delay['status'] == 'accepted';

  String get delayReason => (_delay['reason'] ?? '').toString();
  String get delayReasonLabel => orderDelayReasonLabel(delayReason);
  String get delayNote => (_delay['note'] ?? '').toString().trim();
  DateTime? get delayProposedDate {
    final value = _delay['proposedDate'];
    return value is Timestamp ? value.toDate() : null;
  }

  DateTime? get delayReportedAt {
    final value = _delay['reportedAt'];
    return value is Timestamp ? value.toDate() : null;
  }

  bool get reviewed => data['reviewedAt'] != null;

  String get displayId => orderDisplayId(id, createdAt);

  /// When the order entered its current status. Only the farmer changes an
  /// order after it is placed, and each change stamps updatedAt.
  DateTime? get statusChangedAt => switch (status) {
    'pending' => createdAt,
    'confirmed' => confirmedAt ?? updatedAt,
    'shipped' => shippedAt ?? updatedAt,
    'completed' => completedAt ?? updatedAt,
    'rejected' => rejectedAt ?? updatedAt,
    'cancelled' => cancelledAt ?? updatedAt,
    _ => updatedAt,
  };

  /// Time of the latest change the *other* party made to this order, in ms
  /// since epoch — what the unseen badge on a status tab counts. 0 when the
  /// order's current status is the viewer's own doing: a buyer placed their
  /// own pending order, and a farmer confirmed/shipped/completed their own.
  int unseenActivityMs(OrderRole role) {
    // Placing and cancelling are the buyer's; every other change is the
    // farmer's.
    final byFarmer = status != 'pending' && status != 'cancelled';
    final mine = role == OrderRole.farmer ? byFarmer : !byFarmer;
    if (mine) return 0;
    return statusChangedAt?.millisecondsSinceEpoch ?? 0;
  }

  /// Short progress line under a shipped order.
  String get shippedProgressLabel =>
      isPickup ? 'Ready for pick-up' : 'Delivery in progress';
}
