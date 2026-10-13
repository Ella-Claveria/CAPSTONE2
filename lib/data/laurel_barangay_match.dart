import 'laurel_barangays.dart';

/// Matching a looked-up address to one of Laurel's barangays
/// ([kLaurelBarangays]) by name.
///
/// An address lookup does not put the barangay in any one fixed field, and
/// spells it its own way ("Brgy. 2", "Sta. Maria", "Busobuso", "Jose
/// Leviste"). So every candidate field is compared, after the spelling is
/// evened out — and a barangay is only suggested when the candidates point
/// to exactly one. Two different barangays in the same address (it
/// happens around the town proper) is treated as "not sure", never
/// settled by guessing. Nothing here uses distance.

// Other names the same barangay goes by. Keys are already normalized.
const Map<String, String> _aliases = {
  'joseleviste': 'J. Leviste',
  'leviste': 'J. Leviste',
  'poblacion1': 'Barangay 1',
  'poblacion2': 'Barangay 2',
  'poblacion3': 'Barangay 3',
  'poblacion4': 'Barangay 4',
  'poblacion5': 'Barangay 5',
  'bugaanwest': 'Bugaan West',
  'bugaaneast': 'Bugaan East',
};

/// Evens out capitals, spacing, punctuation and the usual abbreviations:
/// "Brgy.  2" and "barangay 2" both become "barangay2"; "Sta. Maria" and
/// "Santa Maria" both become "santamaria".
String normalizeBarangayName(String name) {
  var value = ' ${name.toLowerCase()} ';
  value = value
      .replaceAll(RegExp(r'\bbrgy\.?\s'), ' barangay ')
      .replaceAll(RegExp(r'\bbgy\.?\s'), ' barangay ')
      .replaceAll(RegExp(r'\bsta\.?\s'), ' santa ')
      .replaceAll(RegExp(r'\bsto\.?\s'), ' santo ')
      .replaceAll(RegExp(r'\b(pob\.|poblacion)\s'), ' poblacion ');
  return value.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

final Map<String, String> _byKey = {
  for (final name in kLaurelBarangays) normalizeBarangayName(name): name,
  ..._aliases,
};

/// The supported barangay one address field names, or null.
String? laurelBarangayNamed(String? field) {
  if (field == null || field.trim().isEmpty) return null;
  final key = normalizeBarangayName(field);
  final direct = _byKey[key];
  if (direct != null) return direct;
  // "Barangay Gulod" for a barangay simply listed as "Gulod".
  if (key.startsWith('barangay')) return _byKey[key.substring(8)];
  return null;
}

/// The one supported barangay that [candidates] (the address fields that
/// might hold a barangay) agree on — or null when none of them names one,
/// or they name more than one.
String? matchLaurelBarangay(Iterable<String?> candidates) {
  final found = <String>{};
  for (final candidate in candidates) {
    final match = laurelBarangayNamed(candidate);
    if (match != null) found.add(match);
  }
  return found.length == 1 ? found.single : null;
}

/// Whether a looked-up municipality/city name is Laurel.
bool isLaurelMunicipality(String? name) {
  if (name == null) return false;
  final key = name.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  return key == 'laurel' || key == 'municipalityoflaurel';
}
