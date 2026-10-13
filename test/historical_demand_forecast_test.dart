// Historical demand import (validation only — nothing is saved here) and
// the per-commodity monthly forecast built on it and on completed orders.
import 'package:agritrade/data/commodity_master_list.dart';
import 'package:agritrade/screen/historical_demand_import.dart';
import 'package:agritrade/services/historical_demand_service.dart';
import 'package:flutter_test/flutter_test.dart';

const supported = [
  Commodity('Chicken', 'Livestock', 'kg liveweight'),
  Commodity('Corn', 'Grains', 'kg'),
  Commodity('Egg', 'Livestock', 'piece'),
];

final now = DateTime(2026, 10, 10);

HistoricalDemandImportResult validate(List<List<String>> table) =>
    HistoricalDemandService.validate(table, supported: supported, now: now);

const header = [
  'Year',
  'Month',
  'Commodity',
  'Category',
  'Quantity Sold',
  'Unit',
];

HistoricalDemandRecord corn(int year, int month, double quantity) =>
    HistoricalDemandRecord(
      year: year,
      month: month,
      commodity: 'Corn',
      category: 'Grains',
      quantity: quantity,
      unit: 'kg',
    );

void main() {
  group('import validation', () {
    test('a file without the required columns is rejected, naming them', () {
      final result = validate([
        ['Year', 'Month', 'Commodity'],
        ['2025', '12', 'Corn'],
      ]);
      expect(result.missingColumns, ['Category', 'Quantity Sold', 'Unit']);
      expect(result.rows, isEmpty);
    });

    test('valid rows are normalized', () {
      final result = validate([
        [
          ' year',
          'MONTH',
          'commodity',
          'Category',
          'Quantity',
          'unit',
          'Average Price',
          'Location',
          'Source',
        ],
        [
          '2025',
          'December',
          'corn',
          'grains',
          '1,250.5',
          'KGS',
          '₱32.50',
          'Laurel',
          'Municipal Agriculture Office',
        ],
        [
          '2025.0',
          '3',
          'CHICKEN',
          'Livestock',
          '80',
          'kg liveweight',
          '',
          '',
          '',
        ],
        ['2024', 'Sep', 'Egg', 'livestock', '1200', 'pcs', '', '', ''],
      ]);
      expect(result.missingColumns, isEmpty);
      expect(result.invalidCount, 0);
      final first = result.validRecords.first;
      expect(first.year, 2025);
      expect(first.month, 12);
      expect(first.commodity, 'Corn');
      expect(first.category, 'Grains');
      expect(first.quantity, 1250.5);
      expect(first.unit, 'kg');
      expect(first.averagePrice, 32.5);
      expect(first.location, 'Laurel');
      expect(result.validRecords[1].commodity, 'Chicken');
      expect(result.validRecords[2].month, 9);
      expect(result.validRecords[2].unit, 'piece');
    });

    test('each invalid row says what is wrong with it', () {
      final result = validate([
        header,
        ['2025', '12', 'Dragonfruit', 'Fruits', '10', 'kg'],
        ['2025', '13', 'Corn', 'Grains', '10', 'kg'],
        ['abc', '5', 'Corn', 'Grains', '10', 'kg'],
        ['2025', '5', 'Corn', 'Vegetables', '10', 'kg'],
        ['2025', '5', 'Corn', 'Grains', '-4', 'kg'],
        ['2025', '5', 'Corn', 'Grains', 'many', 'kg'],
        ['2025', '5', 'Corn', 'Grains', '10', 'sacks'],
        ['2025', '5', 'Chicken', 'Livestock', '10', 'head'],
        ['2026', '10', 'Corn', 'Grains', '10', 'kg'],
        ['2027', '1', 'Corn', 'Grains', '10', 'kg'],
        ['', '', '', '', '', ''],
        ['2025', '6', 'Corn', 'Grains', '10', 'kg'],
        ['2025', '6', 'Corn', 'Grains', '99', 'kg'],
      ]);
      String errorsOf(int rowNumber) => result.rows
          .firstWhere((r) => r.rowNumber == rowNumber)
          .errors
          .join(' ');
      expect(errorsOf(2), contains('not in Supported Products'));
      expect(errorsOf(3), contains('is not a month'));
      expect(errorsOf(4), contains('not a valid year'));
      expect(errorsOf(5), contains("does not match Corn's category (Grains)"));
      expect(errorsOf(6), contains('more than 0'));
      expect(errorsOf(7), contains('is not a number'));
      expect(errorsOf(8), contains('is not supported'));
      expect(errorsOf(9), contains("does not match Chicken's unit"));
      // The current month and future months are not history.
      expect(errorsOf(10), contains('has not ended yet'));
      expect(errorsOf(11), contains('has not ended yet'));
      // The blank line is skipped, not reported. The second June row
      // repeats the first.
      expect(result.rows.length, 12);
      expect(result.rows.last.errors.join(), contains('Repeats row'));
      expect(result.validRecords.length, 1);
    });

    test('re-importing the same month, commodity, location and source maps '
        'to the same record', () {
      const a = HistoricalDemandRecord(
        year: 2025,
        month: 3,
        commodity: 'Corn',
        category: 'Grains',
        quantity: 10,
        unit: 'kg',
        location: 'Laurel',
        source: 'MAO',
      );
      const b = HistoricalDemandRecord(
        year: 2025,
        month: 3,
        commodity: 'Corn',
        category: 'Grains',
        quantity: 999,
        unit: 'kg',
        location: 'laurel ',
        source: 'mao',
      );
      expect(a.id, b.id);
      expect(a.id, '2025-03_corn_laurel_mao');
      expect(corn(2025, 3, 1).id, isNot(a.id));
      // Stored and read back unchanged.
      final restored = HistoricalDemandRecord.fromMap(a.toMap())!;
      expect(restored.quantity, 10);
      expect(restored.location, 'Laurel');
      expect(HistoricalDemandRecord.fromMap({'year': 2025}), isNull);
    });

    test('CSV reading handles quotes, commas inside them and blank lines', () {
      final table = readCsvTable(
        '﻿Year,Month,Commodity,Source\r\n'
        '2025,12,Corn,"Office, Municipal ""MAO"""\n'
        '\n'
        '2025,11,Corn,\n',
      );
      expect(table, [
        ['Year', 'Month', 'Commodity', 'Source'],
        ['2025', '12', 'Corn', 'Office, Municipal "MAO"'],
        ['2025', '11', 'Corn', ''],
      ]);
    });
  });
}
