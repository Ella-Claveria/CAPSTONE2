// The sample/template file for importing historical seasonal demand
// (seed_data/historical_demand_template.csv) must always pass the Admin
// import's own checks, so it can be used as the starting point for real
// DA Laurel records.
import 'dart:io';

import 'package:agritrade/data/commodity_master_list.dart';
import 'package:agritrade/services/historical_demand_service.dart';
import 'package:agritrade/screen/historical_demand_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the template imports without errors', () {
    final table = readCsvTable(
      File('seed_data/historical_demand_template.csv').readAsStringSync(),
    );
    final result = HistoricalDemandService.validate(
      table,
      supported: CommodityRegistry.instance.all,
      now: DateTime(2026, 10, 18),
    );
    expect(result.missingColumns, isEmpty);
    expect(result.rows.where((r) => r.errors.isNotEmpty), isEmpty);
    expect(result.rows, hasLength(18));
  });
}
