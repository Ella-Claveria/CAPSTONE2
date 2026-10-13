/// How reports, confirmed violations and user accounts are tied together
/// in the Admin Portal: always by the reported user's account id (uid),
/// never by a name or an email, and never through a second copy of the
/// user. Pure, so it can be tested without Firestore.
library;

/// The uid of the account a report is about.
///
/// `reportedUserId` is the reported account: the other participant of a
/// chat report (a farmer when a buyer reports, a buyer when a farmer
/// does), and the buyer who wrote a reported review. `farmerId` is only a
/// fallback, for older listing reports that named the listing's farmer
/// and nothing else — on a review report it is the farmer who REPORTED,
/// not the one reported.
String reportedUserIdOf(Map<String, dynamic> report) {
  final reported = (report['reportedUserId'] ?? '').toString().trim();
  if (reported.isNotEmpty) return reported;
  return (report['farmerId'] ?? '').toString().trim();
}

/// A report's place in the workflow: 'pending', 'under_review' or
/// 'resolved'. 'dismissed' is the value an earlier version wrote for a
/// resolved report.
String reportStageOf(Map<String, dynamic> report) {
  final status = (report['status'] ?? 'pending').toString();
  return status == 'dismissed' ? 'resolved' : status;
}

/// The decision recorded on a report, if any ('warning', 'suspended',
/// 'dismissed', …).
String? reportDecisionOf(Map<String, dynamic> report) =>
    (report['moderationAction'] ?? report['action'])?.toString();

/// Where an account stands with moderation. Separate from whether the
/// account can be used (its account status): a confirmed violation does
/// not by itself suspend or ban anyone.
enum ModerationStatus {
  /// No report stands against the account.
  clear,

  /// A report was filed and has not been looked at yet. Only an
  /// allegation.
  reported,

  /// An Admin is reviewing a report against the account.
  underReview,

  /// An Admin confirmed a violation on at least one report.
  confirmedViolation,
}

extension ModerationStatusLabel on ModerationStatus {
  String get label => switch (this) {
    ModerationStatus.clear => 'Clear',
    ModerationStatus.reported => 'Reported',
    ModerationStatus.underReview => 'Under Review',
    ModerationStatus.confirmedViolation => 'Confirmed Violation',
  };
}

/// One account's moderation record, counted from the reports about it.
class ModerationSummary {
  /// Every report filed about the account, whatever became of it.
  final int reportsReceived;

  /// Reports not yet opened for review.
  final int pending;
  final int underReview;

  /// Reports on which an Admin confirmed a violation.
  final int confirmedViolations;
  final int warnings;

  const ModerationSummary({
    this.reportsReceived = 0,
    this.pending = 0,
    this.underReview = 0,
    this.confirmedViolations = 0,
    this.warnings = 0,
  });

  static const ModerationSummary none = ModerationSummary();

  /// A confirmed violation stays on the account's record, so it shows
  /// first; then a review in progress; then a report waiting for one.
  /// Reports that were dismissed or resolved with no violation leave the
  /// account clear.
  ModerationStatus get status {
    if (confirmedViolations > 0) return ModerationStatus.confirmedViolation;
    if (underReview > 0) return ModerationStatus.underReview;
    if (pending > 0) return ModerationStatus.reported;
    return ModerationStatus.clear;
  }
}

/// Each reported account's [ModerationSummary], by uid. An account that
/// is not in the result has never been reported.
Map<String, ModerationSummary> summarizeModeration(
  Iterable<Map<String, dynamic>> reports,
) {
  final received = <String, int>{};
  final pending = <String, int>{};
  final underReview = <String, int>{};
  final confirmed = <String, int>{};
  final warnings = <String, int>{};
  void count(Map<String, int> into, String uid) =>
      into[uid] = (into[uid] ?? 0) + 1;

  for (final report in reports) {
    final uid = reportedUserIdOf(report);
    if (uid.isEmpty) continue;
    count(received, uid);
    switch (reportStageOf(report)) {
      case 'pending':
        count(pending, uid);
      case 'under_review':
        count(underReview, uid);
    }
    if (report['violationConfirmed'] == true) count(confirmed, uid);
    if (reportDecisionOf(report) == 'warning') count(warnings, uid);
  }
  return {
    for (final uid in received.keys)
      uid: ModerationSummary(
        reportsReceived: received[uid] ?? 0,
        pending: pending[uid] ?? 0,
        underReview: underReview[uid] ?? 0,
        confirmedViolations: confirmed[uid] ?? 0,
        warnings: warnings[uid] ?? 0,
      ),
  };
}

/// Whether an account can be used: 'active', 'suspended', 'banned' or
/// 'deactivated'. A missing value is an active account.
String accountStatusOf(Map<String, dynamic>? user) {
  final status = (user?['accountStatus'] ?? 'active')
      .toString()
      .trim()
      .toLowerCase();
  return status.isEmpty ? 'active' : status;
}

String accountStatusLabel(String status) => switch (status) {
  'active' => 'Active',
  'suspended' => 'Suspended',
  'banned' => 'Banned',
  'deactivated' => 'Deactivated',
  _ =>
    status.isEmpty ? 'Active' : status[0].toUpperCase() + status.substring(1),
};

/// What an Admin can do once a violation is confirmed.
enum ViolationAction {
  recordOnly('violation_recorded', 'Record Violation Only'),
  warning('warning', 'Issue Warning'),
  hideListing('hidden', 'Hide Related Listing'),
  removeReview('review_removed', 'Remove Reported Review'),
  suspend('suspended', 'Suspend Account'),
  ban('banned', 'Ban Account');

  const ViolationAction(this.code, this.label);

  /// The value saved on the report as its `moderationAction`.
  final String code;
  final String label;

  String get severity => switch (this) {
    ViolationAction.recordOnly || ViolationAction.warning => 'minor',
    ViolationAction.hideListing || ViolationAction.removeReview => 'moderate',
    ViolationAction.suspend => 'serious',
    ViolationAction.ban => 'critical',
  };
}

/// The actions that apply to a report: nothing about a listing unless the
/// report names one, nothing about a review unless it names one.
List<ViolationAction> violationActionsFor(Map<String, dynamic> report) {
  bool has(String key) => (report[key] ?? '').toString().trim().isNotEmpty;
  final listing = has('productId');
  final review = has('reviewId');
  return [
    ViolationAction.recordOnly,
    ViolationAction.warning,
    if (review) ViolationAction.removeReview,
    // On a review report the listing is the reporter's own, not the
    // reported buyer's.
    // An Admin hides a listing, never deletes it.
    if (listing && !review) ViolationAction.hideListing,
    if (reportedUserIdOf(report).isNotEmpty) ...[
      ViolationAction.suspend,
      ViolationAction.ban,
    ],
  ];
}

/// The violation record written when an Admin confirms a violation: tied
/// to the reported account by uid and to the report it came from.
Map<String, dynamic> violationRecord({
  required String reportId,
  required Map<String, dynamic> report,
  required String? reportedUserRole,
  required ViolationAction action,
  required String reason,
  required String? confirmedBy,
  required Object confirmedAt,
}) {
  String? text(String key) {
    final value = (report[key] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  return {
    'reportedUserId': reportedUserIdOf(report),
    'reportedUserRole': reportedUserRole,
    'sourceReportId': reportId,
    'violationType': text('issueType') ?? text('reason') ?? 'General Report',
    'reason': reason,
    // What the reporter wrote: the evidence the decision was made on.
    'evidence': text('description'),
    'relatedListingId': text('productId'),
    'relatedOrderId': text('relatedOrderId') ?? text('orderId'),
    'relatedConversationId': text('conversationId'),
    'relatedReviewId': text('reviewId'),
    'actionTaken': action.code,
    'severity': action.severity,
    'confirmedBy': confirmedBy,
    'confirmedAt': confirmedAt,
    'status': 'confirmed',
  };
}
