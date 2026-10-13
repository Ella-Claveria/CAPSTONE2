import 'package:agritrade/services/audit_log_service.dart';
import 'package:agritrade/services/moderation_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the reported account is found by its uid', () {
    test('a chat report: the other participant', () {
      expect(
        reportedUserIdOf({
          'reporterId': 'farmer-a',
          'reportedUserId': 'buyer-b',
          'farmerId': 'buyer-b',
          'targetType': 'buyer',
        }),
        'buyer-b',
      );
    });

    test('a review report: the buyer who wrote it, not the farmer '
        'who reported it', () {
      expect(
        reportedUserIdOf({
          'reporterId': 'farmer-a',
          'reportedUserId': 'buyer-b',
          'farmerId': 'farmer-a',
          'targetType': 'review',
        }),
        'buyer-b',
      );
    });

    test('an older listing report that names only the farmer', () {
      expect(
        reportedUserIdOf({'farmerId': 'farmer-a', 'productId': 'p1'}),
        'farmer-a',
      );
    });

    test('no account on record', () {
      expect(reportedUserIdOf({'reporterId': 'x'}), '');
    });
  });

  group('moderation status follows the reports about the account', () {
    Map<String, dynamic> report(
      String uid, {
      String status = 'pending',
      bool violation = false,
      String? action,
    }) => {
      'reportedUserId': uid,
      'status': status,
      'violationConfirmed': violation,
      'moderationAction': ?action,
    };

    test('never reported: clear, and not in the summaries', () {
      expect(summarizeModeration(const [])['juan'], isNull);
      expect(ModerationSummary.none.status, ModerationStatus.clear);
    });

    test('an unopened report: Reported', () {
      final juan = summarizeModeration([report('juan')])['juan']!;
      expect(juan.status, ModerationStatus.reported);
      expect(juan.reportsReceived, 1);
    });

    test('a report being reviewed: Under Review', () {
      final juan = summarizeModeration([
        report('juan', status: 'under_review'),
      ])['juan']!;
      expect(juan.status, ModerationStatus.underReview);
      expect(juan.underReview, 1);
    });

    test('a confirmed violation: Confirmed Violation', () {
      final juan = summarizeModeration([
        report('juan', status: 'resolved', violation: true, action: 'warning'),
      ])['juan']!;
      expect(juan.status, ModerationStatus.confirmedViolation);
      expect(juan.confirmedViolations, 1);
      expect(juan.warnings, 1);
    });

    test('dismissed or resolved with no violation: clear again', () {
      final juan = summarizeModeration([
        report('juan', status: 'resolved', action: 'dismissed'),
        report('juan', status: 'resolved', action: 'no_violation'),
        report('juan', status: 'dismissed'),
      ])['juan']!;
      expect(juan.status, ModerationStatus.clear);
      expect(juan.reportsReceived, 3);
      expect(juan.confirmedViolations, 0);
    });

    test('one account\'s reports never count against another', () {
      final all = summarizeModeration([
        report('juan', status: 'resolved', violation: true),
        report('maria'),
      ]);
      expect(all['juan']!.status, ModerationStatus.confirmedViolation);
      expect(all['maria']!.status, ModerationStatus.reported);
    });

    test('a farmer who reports a review is not the one reported', () {
      final all = summarizeModeration([
        {
          'reporterId': 'farmer-a',
          'reportedUserId': 'buyer-b',
          'farmerId': 'farmer-a',
          'status': 'pending',
        },
      ]);
      expect(all.containsKey('farmer-a'), isFalse);
      expect(all['buyer-b']!.status, ModerationStatus.reported);
    });
  });

  test('a violation does not change whether the account can be used', () {
    // Account status is its own field: absent means active.
    expect(accountStatusOf(null), 'active');
    expect(accountStatusOf({'accountStatus': 'Suspended'}), 'suspended');
    expect(accountStatusLabel('banned'), 'Banned');
    expect(accountStatusLabel('deactivated'), 'Deactivated');
  });

  group('only the actions that apply to the case are offered', () {
    test('a report about a buyer: nothing about a listing', () {
      final actions = violationActionsFor({
        'reportedUserId': 'buyer-b',
        'targetType': 'buyer',
      });
      expect(actions, [
        ViolationAction.recordOnly,
        ViolationAction.warning,
        ViolationAction.suspend,
        ViolationAction.ban,
      ]);
    });

    test('a report about a listing: it can be hidden too', () {
      final actions = violationActionsFor({
        'reportedUserId': 'farmer-a',
        'productId': 'p1',
      });
      expect(actions, contains(ViolationAction.hideListing));
      expect(actions, isNot(contains(ViolationAction.removeReview)));
    });

    test('a report about a review: remove the review, not the '
        'reporter\'s listing', () {
      final actions = violationActionsFor({
        'reportedUserId': 'buyer-b',
        'farmerId': 'farmer-a',
        'productId': 'p1',
        'reviewId': 'r1',
      });
      expect(actions, contains(ViolationAction.removeReview));
      expect(actions, isNot(contains(ViolationAction.hideListing)));
    });
  });

  test('a violation record is tied to the user and its source report', () {
    final record = violationRecord(
      reportId: 'report_001',
      report: {
        'reportedUserId': 'xyz123',
        'issueType': 'Bogus Buyer',
        'description': 'Did not show up twice.',
        'conversationId': 'chat_9',
      },
      reportedUserRole: 'buyer',
      action: ViolationAction.suspend,
      reason: 'Repeated no-shows.',
      confirmedBy: 'admin-1',
      confirmedAt: DateTime(2026, 10, 11),
    );
    expect(record['reportedUserId'], 'xyz123');
    expect(record['sourceReportId'], 'report_001');
    expect(record['violationType'], 'Bogus Buyer');
    expect(record['evidence'], 'Did not show up twice.');
    expect(record['relatedConversationId'], 'chat_9');
    expect(record['relatedListingId'], isNull);
    expect(record['actionTaken'], 'suspended');
    expect(record['confirmedBy'], 'admin-1');
    expect(record['status'], 'confirmed');
  });

  test('every decision has an audit action', () {
    expect(
      AuditAction.all,
      containsAll([
        AuditAction.startReportReview,
        AuditAction.resolveReport,
        AuditAction.confirmViolation,
        AuditAction.suspendAccount,
        AuditAction.banAccount,
        AuditAction.reactivateAccount,
      ]),
    );
  });
}
