import 'market_price_helpers.dart';

// Where a farmer delivers a listing, and whether a buyer's general location
// falls inside it. Stored on the product as one map, 'deliveryCoverage'
// (see DeliveryCoverage.toMap), next to the existing 'deliveryAvailable'
// and 'pickupOnly' flags ('pickupOnly' has always meant "pick-up is
// available" everywhere it is read).
//
// Coverage is by general area only — barangay, municipality/city, province
// — never an exact address or route. There is no courier integration, so
// the delivery fee is only ever the farmer's fixed amount or "to be
// arranged"; nothing here estimates shipping.

/// How far a listing's standard delivery reaches.
enum DeliveryCoverageType {
  sameBarangay('sameBarangay', 'Same Barangay'),
  municipality('municipality', 'Within Municipality/City'),
  nearby('nearby', 'Nearby Municipalities/Cities'),
  custom('custom', 'Custom Areas');

  final String id;
  final String label;
  const DeliveryCoverageType(this.id, this.label);

  static DeliveryCoverageType fromId(String? id) => values.firstWhere(
    (t) => t.id == id,
    orElse: () => DeliveryCoverageType.municipality,
  );
}

enum DeliveryFeeType {
  fixed('fixed'),
  arranged('arranged');

  final String id;
  const DeliveryFeeType(this.id);

  static DeliveryFeeType fromId(String? id) =>
      id == 'fixed' ? DeliveryFeeType.fixed : DeliveryFeeType.arranged;
}

/// A municipality/city, with its province so same-named towns in
/// different provinces aren't confused.
class DeliveryArea {
  final String name;
  final String province;

  const DeliveryArea(this.name, [this.province = '']);

  factory DeliveryArea.fromMap(Map<String, dynamic> map) => DeliveryArea(
    (map['name'] ?? '').toString(),
    (map['province'] ?? '').toString(),
  );

  Map<String, dynamic> toMap() => {'name': name, 'province': province};

  String get label => province.isEmpty ? name : '$name, $province';

  /// The same place, however it was spelled ("City of Tanauan" vs
  /// "Tanauan City").
  bool matches(String otherName, String otherProvince) {
    if (normalizePlace(name) != normalizePlace(otherName)) return false;
    final a = normalizeProvince(province);
    final b = normalizeProvince(otherProvince);
    return a.isEmpty || b.isEmpty || a == b;
  }

  @override
  bool operator ==(Object other) =>
      other is DeliveryArea &&
      normalizePlace(name) == normalizePlace(other.name) &&
      normalizeProvince(province) == normalizeProvince(other.province);

  @override
  int get hashCode =>
      Object.hash(normalizePlace(name), normalizeProvince(province));
}

/// Where farmers are registered. Every AgriTrade+ farmer is in Laurel,
/// Batangas (see AuthService registration), which is also the fallback
/// origin for listings saved before delivery coverage existed.
const DeliveryArea kDefaultFarmOrigin = DeliveryArea('Laurel', 'Batangas');

/// "Nearby Municipalities/Cities" for each farm municipality — the towns
/// immediately around it. Keyed by normalized "municipality|province".
/// Edit this list to change what "Nearby" covers.
const Map<String, List<DeliveryArea>> kNearbyDeliveryAreas = {
  'laurel|batangas': [
    DeliveryArea('Agoncillo', 'Batangas'),
    DeliveryArea('Talisay', 'Batangas'),
    DeliveryArea('Lemery', 'Batangas'),
    DeliveryArea('Calaca', 'Batangas'),
    DeliveryArea('Tanauan', 'Batangas'),
    DeliveryArea('Tagaytay', 'Cavite'),
  ],
};

/// Offline fallback for the Custom Areas picker when the PSGC list can't
/// be loaded: Batangas plus the neighbouring Cavite/Laguna towns.
const List<DeliveryArea> kFallbackDeliveryAreas = [
  DeliveryArea('Agoncillo', 'Batangas'),
  DeliveryArea('Alitagtag', 'Batangas'),
  DeliveryArea('Balayan', 'Batangas'),
  DeliveryArea('Balete', 'Batangas'),
  DeliveryArea('Batangas City', 'Batangas'),
  DeliveryArea('Bauan', 'Batangas'),
  DeliveryArea('Calaca', 'Batangas'),
  DeliveryArea('Calatagan', 'Batangas'),
  DeliveryArea('Cuenca', 'Batangas'),
  DeliveryArea('Ibaan', 'Batangas'),
  DeliveryArea('Laurel', 'Batangas'),
  DeliveryArea('Lemery', 'Batangas'),
  DeliveryArea('Lian', 'Batangas'),
  DeliveryArea('Lipa City', 'Batangas'),
  DeliveryArea('Lobo', 'Batangas'),
  DeliveryArea('Mabini', 'Batangas'),
  DeliveryArea('Malvar', 'Batangas'),
  DeliveryArea('Mataasnakahoy', 'Batangas'),
  DeliveryArea('Nasugbu', 'Batangas'),
  DeliveryArea('Padre Garcia', 'Batangas'),
  DeliveryArea('Rosario', 'Batangas'),
  DeliveryArea('San Jose', 'Batangas'),
  DeliveryArea('San Juan', 'Batangas'),
  DeliveryArea('San Luis', 'Batangas'),
  DeliveryArea('San Nicolas', 'Batangas'),
  DeliveryArea('San Pascual', 'Batangas'),
  DeliveryArea('Santa Teresita', 'Batangas'),
  DeliveryArea('Santo Tomas', 'Batangas'),
  DeliveryArea('Taal', 'Batangas'),
  DeliveryArea('Talisay', 'Batangas'),
  DeliveryArea('Tanauan City', 'Batangas'),
  DeliveryArea('Taysan', 'Batangas'),
  DeliveryArea('Tingloy', 'Batangas'),
  DeliveryArea('Tuy', 'Batangas'),
  DeliveryArea('Alfonso', 'Cavite'),
  DeliveryArea('Amadeo', 'Cavite'),
  DeliveryArea('Mendez', 'Cavite'),
  DeliveryArea('Silang', 'Cavite'),
  DeliveryArea('Tagaytay City', 'Cavite'),
  DeliveryArea('Calamba City', 'Laguna'),
];

/// A buyer's general location (from the order form's location picker or
/// their saved profile).
class BuyerArea {
  final String barangay;
  final String city;
  final String province;

  const BuyerArea({this.barangay = '', this.city = '', this.province = ''});

  bool get isKnown => city.trim().isNotEmpty;

  String get label =>
      [barangay, city, province].where((s) => s.trim().isNotEmpty).join(', ');
}

enum DeliveryReach {
  /// Inside the farmer's standard coverage.
  covered,

  /// Outside it — delivery only if arranged with the farmer in Messages.
  outside,

  /// The buyer's location isn't set, so coverage can't be checked yet.
  unknownLocation,
}

/// A listing's delivery setup.
class DeliveryCoverage {
  final DeliveryCoverageType type;
  final List<DeliveryArea> customAreas;
  final DeliveryFeeType feeType;
  final num? fee;

  /// The farm's own barangay and municipality — what Same Barangay and
  /// Within Municipality are measured from.
  final String originBarangay;
  final DeliveryArea origin;

  /// False for listings saved before coverage existed; they're treated as
  /// Within Municipality with the fee to be arranged.
  final bool configured;

  const DeliveryCoverage({
    required this.type,
    this.customAreas = const [],
    required this.feeType,
    this.fee,
    this.originBarangay = '',
    this.origin = kDefaultFarmOrigin,
    this.configured = true,
  });

  /// The coverage for a product doc. Delivery Available without a saved
  /// coverage never means nationwide: it falls back to the farm's own
  /// municipality, fee to be arranged.
  factory DeliveryCoverage.fromProduct(Map<String, dynamic> product) {
    final raw = product['deliveryCoverage'];
    if (raw is! Map) {
      return const DeliveryCoverage(
        type: DeliveryCoverageType.municipality,
        feeType: DeliveryFeeType.arranged,
        configured: false,
      );
    }
    final map = Map<String, dynamic>.from(raw);
    final areas = (map['areas'] is List)
        ? (map['areas'] as List)
              .whereType<Map>()
              .map((a) => DeliveryArea.fromMap(Map<String, dynamic>.from(a)))
              .where((a) => a.name.trim().isNotEmpty)
              .toList()
        : <DeliveryArea>[];
    final feeType = DeliveryFeeType.fromId(map['feeType']?.toString());
    final fee = map['fee'] as num?;
    final originName = (map['originMunicipality'] ?? '').toString();
    return DeliveryCoverage(
      type: DeliveryCoverageType.fromId(map['type']?.toString()),
      customAreas: areas,
      // A "fixed" fee with no valid amount is treated as to be arranged.
      feeType: feeType == DeliveryFeeType.fixed && fee != null && fee >= 0
          ? DeliveryFeeType.fixed
          : DeliveryFeeType.arranged,
      fee: fee,
      originBarangay: (map['originBarangay'] ?? '').toString(),
      origin: originName.isEmpty
          ? kDefaultFarmOrigin
          : DeliveryArea(originName, (map['originProvince'] ?? '').toString()),
    );
  }

  Map<String, dynamic> toMap() => {
    'type': type.id,
    if (type == DeliveryCoverageType.custom)
      'areas': customAreas.map((a) => a.toMap()).toList(),
    'feeType': feeType.id,
    if (feeType == DeliveryFeeType.fixed) 'fee': fee,
    'originBarangay': originBarangay,
    'originMunicipality': origin.name,
    'originProvince': origin.province,
  };

  bool get feeKnown => feeType == DeliveryFeeType.fixed && fee != null;

  /// The towns the coverage reaches (empty for Same Barangay, which is
  /// narrower than a town).
  List<DeliveryArea> get areas => switch (type) {
    DeliveryCoverageType.sameBarangay => const [],
    DeliveryCoverageType.municipality => [origin],
    DeliveryCoverageType.nearby => [origin, ...nearbyAreasFor(origin)],
    DeliveryCoverageType.custom => customAreas,
  };

  /// e.g. "Within Laurel", "Laurel and nearby towns", "Laurel, Talisay +2".
  String get areaLabel => switch (type) {
    DeliveryCoverageType.sameBarangay =>
      originBarangay.isEmpty
          ? 'Same barangay only'
          : 'Barangay $originBarangay only',
    DeliveryCoverageType.municipality => 'Within ${origin.name}',
    DeliveryCoverageType.nearby => '${origin.name} and nearby towns',
    DeliveryCoverageType.custom => _customLabel(),
  };

  String _customLabel() {
    if (customAreas.isEmpty) return 'Selected areas';
    final names = customAreas.map((a) => a.name).toList();
    if (names.length <= 2) return names.join(', ');
    return '${names.take(2).join(', ')} +${names.length - 2} more';
  }

  /// "₱50.00" or "To be arranged with seller".
  String get feeLabel =>
      feeKnown ? formatPeso(fee!) : 'To be arranged with seller';

  DeliveryReach reach(BuyerArea buyer) {
    if (!buyer.isKnown) return DeliveryReach.unknownLocation;
    final inOriginTown = origin.matches(buyer.city, buyer.province);
    final covered = switch (type) {
      DeliveryCoverageType.sameBarangay =>
        inOriginTown &&
            originBarangay.isNotEmpty &&
            normalizeBarangay(originBarangay) ==
                normalizeBarangay(buyer.barangay),
      _ => areas.any((a) => a.matches(buyer.city, buyer.province)),
    };
    return covered ? DeliveryReach.covered : DeliveryReach.outside;
  }
}

List<DeliveryArea> nearbyAreasFor(DeliveryArea origin) =>
    kNearbyDeliveryAreas['${normalizePlace(origin.name)}|'
        '${normalizeProvince(origin.province)}'] ??
    const [];

/// "City of Tanauan", "Tanauan City" and "tanauan" → "tanauan".
String normalizePlace(String raw) {
  var s = raw.toLowerCase().trim();
  s = s.replaceAll(RegExp(r'\(.*?\)'), ' ');
  s = s.replaceAll(RegExp(r'^(city|municipality) of\s+'), '');
  s = s.replaceAll(RegExp(r'\s+city$'), '');
  return s.replaceAll(RegExp(r'[^a-z0-9ñ]'), '');
}

/// Metro Manila has no province: the location picker stores the region
/// name ("National Capital Region (NCR)") and geocoding gives "Metro
/// Manila", so all of those count as one.
String normalizeProvince(String raw) {
  final s = raw.toLowerCase();
  if (s.contains('ncr') ||
      s.contains('national capital') ||
      s.contains('metro manila')) {
    return 'metromanila';
  }
  return normalizePlace(raw);
}

/// "Barangay 1 (Pob.)", "Brgy. 1" and "1" → "1".
String normalizeBarangay(String raw) {
  var s = raw.toLowerCase().trim();
  s = s.replaceAll(RegExp(r'\(.*?\)'), ' ');
  s = s.replaceAll(RegExp(r'^(barangay|brgy\.?|bgy\.?)\s*'), '');
  return s.replaceAll(RegExp(r'[^a-z0-9ñ]'), '');
}
