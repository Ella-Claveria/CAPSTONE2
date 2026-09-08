import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Shared formatting + aggregation helpers for the admin Analytics
/// Dashboard and Price Management screens, so both read live Firestore
/// data the same way instead of drifting apart.

final NumberFormat _pesoFormat = NumberFormat.currency(
  locale: 'en_PH',
  symbol: '₱',
  decimalDigits: 2,
);

String formatPeso(num value) => _pesoFormat.format(value);

String timeAgo(Timestamp? ts) {
  if (ts == null) return 'just now';
  final diff = DateTime.now().difference(ts.toDate());
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return DateFormat('MMM d, y').format(ts.toDate());
}

/// Average listed price of live products whose name or category contains
/// [commodityKey] (case-insensitive). Returns null when nothing matches,
/// so callers can show an explicit "no data" state instead of a fake 0.
double? computeLiveAverage(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> products,
  String commodityKey,
) {
  final key = commodityKey.trim().toLowerCase();
  if (key.isEmpty) return null;

  final matches = <double>[];
  for (final doc in products) {
    final data = doc.data();
    final name = (data['name'] ?? '').toString().toLowerCase();
    final category = (data['category'] ?? '').toString().toLowerCase();
    if (!name.contains(key) && !category.contains(key)) continue;

    final raw = data['price'];
    final price = raw is num
        ? raw.toDouble()
        : num.tryParse(raw?.toString() ?? '')?.toDouble();
    if (price != null && price > 0) matches.add(price);
  }

  if (matches.isEmpty) return null;
  return matches.reduce((a, b) => a + b) / matches.length;
}
