import 'package:flutter/foundation.dart';

import '../services/audit_log_service.dart';

/// The sections inside the Admin pages that have more than one view, and
/// which of them is open. Shared by the sidebar's submenus and the pages
/// themselves, so choosing a section in either place shows in both.
///
/// Only pages that really have several views are here: a submenu item
/// always opens something that exists.

/// The User Accounts page's views: the farmers (the Farmer List), and the
/// buyers' accounts.
enum UserAccountsSection { farmers, buyers }

extension UserAccountsSectionLabel on UserAccountsSection {
  String get label => switch (this) {
    UserAccountsSection.farmers => 'Farmers',
    UserAccountsSection.buyers => 'Buyers',
  };
}

/// The Moderation Queue's tabs: the reports, by where each stands.
enum ModerationSection { pending, underReview, resolved }

/// The Violations page's tabs: accounts with a confirmed violation, and
/// listings priced far above their suggested range.
enum ViolationSection { violations, priceFlags }

/// The Audit Log's groups of actions.
enum AuditSection { all, login, adminActions, moderation }

extension ModerationSectionLabel on ModerationSection {
  String get label => switch (this) {
    ModerationSection.pending => 'Pending Reports',
    ModerationSection.underReview => 'Under Review',
    ModerationSection.resolved => 'Resolved Reports',
  };
}

extension ViolationSectionLabel on ViolationSection {
  String get label => switch (this) {
    ViolationSection.violations => 'Violations',
    ViolationSection.priceFlags => 'Price Flags',
  };
}

extension AuditSectionInfo on AuditSection {
  String get label => switch (this) {
    AuditSection.all => 'All Activity',
    AuditSection.login => 'Login Activity',
    AuditSection.adminActions => 'Admin Actions',
    AuditSection.moderation => 'Moderation Actions',
  };

  /// The audit actions this section lists; null for every action.
  List<String>? get actions => switch (this) {
    AuditSection.all => null,
    AuditSection.login => const [
      AuditAction.loginSuccess,
      AuditAction.loginFailed,
      AuditAction.logout,
      AuditAction.newDeviceLogin,
      AuditAction.sessionReplaced,
      AuditAction.sessionForcedLogout,
      AuditAction.sessionRevoked,
      AuditAction.passwordResetRequested,
    ],
    AuditSection.adminActions => const [
      AuditAction.approveFarmer,
      AuditAction.rejectFarmer,
      AuditAction.updateBaselinePrice,
      AuditAction.deleteBaselinePrice,
      AuditAction.importBaselinePrices,
      AuditAction.exportReport,
      AuditAction.sendAnnouncement,
    ],
    AuditSection.moderation => const [
      AuditAction.warnSeller,
      AuditAction.suspendListing,
      AuditAction.removeListing,
      AuditAction.suspendFarmer,
      AuditAction.banFarmer,
      AuditAction.removeReview,
      AuditAction.dismissReport,
      AuditAction.reactivateFarmer,
      AuditAction.restoreListing,
      AuditAction.startReportReview,
      AuditAction.resolveReport,
      AuditAction.confirmViolation,
      AuditAction.suspendAccount,
      AuditAction.banAccount,
      AuditAction.reactivateAccount,
    ],
  };
}

class AdminSubNav {
  AdminSubNav._();

  static final ValueNotifier<UserAccountsSection> accounts = ValueNotifier(
    UserAccountsSection.farmers,
  );

  static final ValueNotifier<ModerationSection> moderation = ValueNotifier(
    ModerationSection.pending,
  );

  static final ValueNotifier<ViolationSection> violations = ValueNotifier(
    ViolationSection.violations,
  );

  static final ValueNotifier<AuditSection> audit = ValueNotifier(
    AuditSection.all,
  );
}
