/// Hides most of an email address for on-screen display, e.g.
/// "agritrade.farmer@gmail.com" -> "agr***@gmail.com". Enough for the user
/// to recognize their own address without showing it in full.
String maskEmail(String email) {
  final trimmed = email.trim();
  final at = trimmed.lastIndexOf('@');
  if (at <= 0) return trimmed;
  final local = trimmed.substring(0, at);
  final shown = local.length > 3 ? 3 : 1;
  return '${local.substring(0, shown)}***${trimmed.substring(at)}';
}
