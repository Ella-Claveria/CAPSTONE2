/// The reasons a user picks from when reporting another user. They differ
/// by who is reporting: a buyer reports a farmer as a seller, a farmer
/// reports a buyer as a customer.
///
/// The chosen reason is saved as the report's `issueType`, which is what
/// the Admin Moderation Queue lists and filters by.
const List<String> kBuyerReportReasons = [
  'Price Gouging',
  'Quality Issues',
  'Misleading Product Information',
  'Wrong or Incomplete Item',
  'Non-fulfillment / Product Not Delivered',
  'Fake or Suspicious Seller',
  'Rude / Inappropriate Behavior',
];

const List<String> kFarmerReportReasons = [
  'Bogus Buyer',
  'Fake Order',
  'No-show for Pick-up',
  'Fake Payment Claim',
  'Spam / Harassment',
  'Abusive or Inappropriate Behavior',
  'Repeated Cancellation',
];

/// The reasons offered to a reporter whose own role is [reporterRole]
/// ('farmer' or 'buyer').
List<String> reportReasonsFor(String reporterRole) =>
    reporterRole == 'farmer' ? kFarmerReportReasons : kBuyerReportReasons;

/// The `targetType` a chat report is filed under: a farmer's report is
/// about a buyer, a buyer's about a farmer.
String reportTargetTypeFor(String reporterRole) =>
    reporterRole == 'farmer' ? 'buyer' : 'farmer';
