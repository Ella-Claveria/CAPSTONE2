import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/commodity_master_list.dart';

/// Historical monthly demand: figures from before AgriTrade+ (or from
/// outside it) that the Admin imports from a spreadsheet, kept in their own
/// `historical_demand` collection.
///
/// They support the demand forecast while the marketplace has little
/// history of its own. They are never turned into orders, never mixed into
/// the `orders` or `market_sales` data, and never changed by live
/// transactions — only another import of the same month, commodity,
/// location and source replaces a record.

/// One month's demand for one commodity, as imported.
class HistoricalDemandRecord {
  final int year;
  final int month;
  final String commodity;
  final String category;
  final double quantity;
  final String unit;
  final double? averagePrice;
  final String location;
  final String source;

  const HistoricalDemandRecord({
    required this.year,
    required this.month,
    required this.commodity,
    required this.category,
    required this.quantity,
    required this.unit,
    this.averagePrice,
    this.location = '',
    this.source = '',
  });

  static String _slug(String text) => text
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  /// The same month, commodity, location and source always map to the same
  /// document, so importing a file twice updates its records instead of
  /// counting them twice.
  String get id => [
    '$year-${month.toString().padLeft(2, '0')}',
    _slug(commodity),
    if (location.isNotEmpty) _slug(location) else 'any',
    if (source.isNotEmpty) _slug(source) else 'unspecified',
  ].join('_');

  Map<String, dynamic> toMap() => {
    'year': year,
    'month': month,
    'commodity': commodity,
    'category': category,
    'quantity': quantity,
    'unit': unit,
    if (averagePrice != null) 'averagePrice': averagePrice,
    if (location.isNotEmpty) 'location': location,
    if (source.isNotEmpty) 'source': source,
  };

  /// Null for a stored document that is not a usable record.
  static HistoricalDemandRecord? fromMap(Map<String, dynamic> data) {
    final year = (data['year'] as num?)?.toInt();
    final month = (data['month'] as num?)?.toInt();
    final quantity = (data['quantity'] as num?)?.toDouble();
    final commodity = (data['commodity'] ?? '').toString().trim();
    if (year == null ||
        month == null ||
        month < 1 ||
        month > 12 ||
        quantity == null ||
        quantity <= 0 ||
        commodity.isEmpty) {
      return null;
    }
    return HistoricalDemandRecord(
      year: year,
      month: month,
      commodity: commodity,
      category: (data['category'] ?? '').toString(),
      quantity: quantity,
      unit: (data['unit'] ?? '').toString(),
      averagePrice: (data['averagePrice'] as num?)?.toDouble(),
      location: (data['location'] ?? '').toString(),
      source: (data['source'] ?? '').toString(),
    );
  }
}

/// One row of an import file after validation: either a [record] ready to
/// save, or the [errors] that explain why it cannot be.
class HistoricalDemandImportRow {
  /// The row's number in the file, counting the header as row 1.
  final int rowNumber;

  /// The cells as they were in the file, by column title.
  final Map<String, String> raw;
  final HistoricalDemandRecord? record;
  final List<String> errors;

  const HistoricalDemandImportRow({
    required this.rowNumber,
    required this.raw,
    required this.record,
    required this.errors,
  });

  bool get isValid => record != null;
}

class HistoricalDemandImportResult {
  /// Required columns the file does not have. When not empty, nothing in
  /// the file could be read and [rows] is empty.
  final List<String> missingColumns;
  final List<HistoricalDemandImportRow> rows;

  const HistoricalDemandImportResult({
    required this.missingColumns,
    required this.rows,
  });

  List<HistoricalDemandRecord> get validRecords => [
    for (final row in rows)
      if (row.isValid) row.record!,
  ];

  int get invalidCount => rows.where((r) => !r.isValid).length;
}

class HistoricalDemandService {
  const HistoricalDemandService._();

  static const String collection = 'historical_demand';

  static const List<String> requiredColumns = [
    'Year',
    'Month',
    'Commodity',
    'Category',
    'Quantity Sold',
    'Unit',
  ];
  static const List<String> optionalColumns = [
    'Average Price',
    'Location',
    'Source',
  ];

  // Column titles are matched without regard to case, spaces or
  // punctuation; a few everyday alternatives are accepted.
  static const Map<String, List<String>> _aliases = {
    'Year': ['year'],
    'Month': ['month'],
    'Commodity': ['commodity', 'product', 'commodityname'],
    'Category': ['category'],
    'Quantity Sold': ['quantitysold', 'quantity', 'qtysold', 'qty'],
    'Unit': ['unit', 'uom'],
    'Average Price': ['averageprice', 'avgprice', 'price'],
    'Location': ['location', 'area', 'barangay', 'municipality'],
    'Source': ['source', 'datasource'],
  };

  static const List<String> _monthNames = [
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
  ];

  // Spellings an Admin is likely to type, mapped to the app's own units.
  static const Map<String, String> _unitSpellings = {
    'kg': 'kg',
    'kgs': 'kg',
    'kilo': 'kg',
    'kilos': 'kg',
    'kilogram': 'kg',
    'kilograms': 'kg',
    'piece': 'piece',
    'pieces': 'piece',
    'pc': 'piece',
    'pcs': 'piece',
    'head': 'head',
    'heads': 'head',
    'kg liveweight': 'kg liveweight',
    'kg live weight': 'kg liveweight',
    'kg lw': 'kg liveweight',
    'liveweight': 'kg liveweight',
  };

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static int? _parseMonth(String text) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return null;
    // "3", "03", and a spreadsheet's "3.0".
    final number = double.tryParse(t);
    if (number != null) {
      return number == number.roundToDouble() && number >= 1 && number <= 12
          ? number.toInt()
          : null;
    }
    for (var i = 0; i < _monthNames.length; i++) {
      if (_monthNames[i] == t ||
          (t.length >= 3 && _monthNames[i].startsWith(t))) {
        return i + 1;
      }
    }
    return null;
  }

  static double? _parseNumber(String text) =>
      double.tryParse(text.trim().replaceAll(',', '').replaceAll('₱', ''));

  /// Validates an import file. [table] is the file's rows as plain text,
  /// header first; [supported] is the Supported Products list; [now]
  /// decides which months are still in the future.
  static HistoricalDemandImportResult validate(
    List<List<String>> table, {
    required List<Commodity> supported,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final rows = [
      for (final row in table)
        if (row.any((cell) => cell.trim().isNotEmpty)) row,
    ];
    if (rows.isEmpty) {
      return const HistoricalDemandImportResult(
        missingColumns: requiredColumns,
        rows: [],
      );
    }

    final header = [for (final cell in rows.first) _norm(cell)];
    final columnOf = <String, int>{};
    for (final entry in _aliases.entries) {
      for (final alias in entry.value) {
        final index = header.indexOf(alias);
        if (index >= 0) {
          columnOf[entry.key] = index;
          break;
        }
      }
    }
    final missing = [
      for (final column in requiredColumns)
        if (!columnOf.containsKey(column)) column,
    ];
    if (missing.isNotEmpty) {
      return HistoricalDemandImportResult(missingColumns: missing, rows: []);
    }

    final byName = {for (final c in supported) c.name.toLowerCase(): c};
    final seen = <String, int>{};
    final result = <HistoricalDemandImportRow>[];

    for (var r = 1; r < rows.length; r++) {
      String cell(String column) {
        final index = columnOf[column];
        return index == null || index >= rows[r].length
            ? ''
            : rows[r][index].trim();
      }

      final raw = {
        for (final column in [...requiredColumns, ...optionalColumns])
          if (columnOf.containsKey(column)) column: cell(column),
      };
      final errors = <String>[];

      // Year
      final yearText = cell('Year');
      final yearNumber = double.tryParse(yearText);
      int? year;
      if (yearText.isEmpty) {
        errors.add('Year is missing.');
      } else if (yearNumber == null ||
          yearNumber != yearNumber.roundToDouble() ||
          yearNumber < 2000) {
        errors.add('Year "$yearText" is not a valid year (2000 or later).');
      } else {
        year = yearNumber.toInt();
      }

      // Month
      final monthText = cell('Month');
      final month = _parseMonth(monthText);
      if (monthText.isEmpty) {
        errors.add('Month is missing.');
      } else if (month == null) {
        errors.add(
          'Month "$monthText" is not a month (use 1–12 or the month\'s name).',
        );
      }

      // Historical means already over: not this month, not a later one.
      if (year != null &&
          month != null &&
          !DateTime(year, month).isBefore(DateTime(today.year, today.month))) {
        errors.add(
          'This month has not ended yet — only past months can be imported.',
        );
      }

      // Commodity, against Supported Products.
      final commodityText = cell('Commodity');
      final commodity = byName[commodityText.toLowerCase()];
      if (commodityText.isEmpty) {
        errors.add('Commodity is missing.');
      } else if (commodity == null) {
        errors.add('"$commodityText" is not in Supported Products.');
      }

      // Category — must be the commodity's own.
      final categoryText = cell('Category');
      if (categoryText.isEmpty) {
        errors.add('Category is missing.');
      } else if (commodity != null &&
          categoryText.toLowerCase() != commodity.category.toLowerCase()) {
        errors.add(
          'Category "$categoryText" does not match ${commodity.name}\'s '
          'category (${commodity.category}).',
        );
      }

      // Quantity
      final quantityText = cell('Quantity Sold');
      final quantity = _parseNumber(quantityText);
      if (quantityText.isEmpty) {
        errors.add('Quantity Sold is missing.');
      } else if (quantity == null) {
        errors.add('Quantity Sold "$quantityText" is not a number.');
      } else if (quantity <= 0) {
        errors.add('Quantity Sold must be more than 0.');
      }

      // Unit — the commodity's own, so quantities stay comparable with
      // what is sold on AgriTrade+.
      final unitText = cell('Unit');
      final unit =
          _unitSpellings[unitText.toLowerCase().replaceAll(
            RegExp(r'\s+'),
            ' ',
          )];
      if (unitText.isEmpty) {
        errors.add('Unit is missing.');
      } else if (unit == null) {
        errors.add(
          'Unit "$unitText" is not supported '
          '(use ${kCommodityUnitOptions.join(', ')}).',
        );
      } else if (commodity != null && unit != commodity.unit) {
        errors.add(
          'Unit "$unitText" does not match ${commodity.name}\'s unit '
          '(${commodity.unit}).',
        );
      }

      // Average Price — optional.
      final priceText = cell('Average Price');
      final price = priceText.isEmpty ? null : _parseNumber(priceText);
      if (priceText.isNotEmpty && (price == null || price < 0)) {
        errors.add('Average Price "$priceText" is not a valid amount.');
      }

      HistoricalDemandRecord? record;
      if (errors.isEmpty) {
        record = HistoricalDemandRecord(
          year: year!,
          month: month!,
          commodity: commodity!.name,
          category: commodity.category,
          quantity: quantity!,
          unit: unit!,
          averagePrice: price,
          location: cell('Location'),
          source: cell('Source'),
        );
        final firstRow = seen[record.id];
        if (firstRow != null) {
          errors.add(
            'Repeats row $firstRow (same month, commodity, location and '
            'source).',
          );
          record = null;
        } else {
          seen[record.id] = r + 1;
        }
      }

      result.add(
        HistoricalDemandImportRow(
          rowNumber: r + 1,
          raw: raw,
          record: record,
          errors: errors,
        ),
      );
    }

    return HistoricalDemandImportResult(missingColumns: const [], rows: result);
  }

  static CollectionReference<Map<String, dynamic>> get _records =>
      FirebaseFirestore.instance.collection(collection);

  /// Every imported record, live.
  static Stream<List<HistoricalDemandRecord>> watch() =>
      _records.snapshots().map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            ?HistoricalDemandRecord.fromMap(doc.data()),
        ],
      );

  /// Saves [records] to `historical_demand` — and only there.
  static Future<void> save(List<HistoricalDemandRecord> records) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    // A Firestore batch holds at most 500 writes.
    for (var start = 0; start < records.length; start += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final record in records.skip(start).take(400)) {
        batch.set(_records.doc(record.id), {
          ...record.toMap(),
          'importedAt': FieldValue.serverTimestamp(),
          'importedBy': uid,
        });
      }
      await batch.commit();
    }
  }
}
