import 'package:agritrade/services/auth_routing_service.dart';
import 'package:agritrade/services/device_trust_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AuthRouteDecision decide(
    Map<String, dynamic>? data, {
    bool verified = true,
  }) =>
      AuthRoutingService.decideFromData(data, emailVerified: verified).decision;

  group('a restored session is re-checked against the account', () {
    test('active accounts go to their own interface', () {
      expect(decide({'role': 'buyer'}), AuthRouteDecision.buyerHome);
      expect(
        decide({'role': 'farmer', 'approvalStatus': 'approved'}),
        AuthRouteDecision.farmerHome,
      );
      // No accountStatus on older accounts means active.
      expect(
        decide({'role': 'buyer', 'accountStatus': 'active'}),
        AuthRouteDecision.buyerHome,
      );
    });

    test('suspended and banned accounts are blocked, whatever the role', () {
      for (final status in ['suspended', 'banned']) {
        expect(
          decide({'role': 'buyer', 'accountStatus': status}),
          AuthRouteDecision.accountRestricted,
        );
        expect(
          decide({
            'role': 'farmer',
            'approvalStatus': 'approved',
            'accountStatus': status,
          }),
          AuthRouteDecision.accountRestricted,
        );
      }
      final banned = AuthRoutingService.decideFromData({
        'role': 'farmer',
        'accountStatus': 'banned',
        'banReason': 'Repeated fake listings',
      });
      expect(banned.message, contains('deactivated'));
      expect(banned.message, contains('Repeated fake listings'));
    });

    test('a farmer who is no longer approved does not reach Farmer Home', () {
      for (final status in ['pending', 'rejected', null]) {
        expect(
          decide({'role': 'farmer', 'approvalStatus': status}),
          AuthRouteDecision.farmerPendingReview,
        );
      }
    });

    test('missing account or role is not let in', () {
      expect(decide(null), AuthRouteDecision.missingProfile);
      expect(decide({'role': 'something'}), AuthRouteDecision.missingRole);
      expect(decide({}), AuthRouteDecision.missingRole);
    });
  });

  group('device identifier', () {
    test('only a hash of the installation id is used', () {
      final hash = DeviceTrustService.hashInstallId('install-abc');
      expect(hash, hasLength(64));
      expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(hash, isNot(contains('install-abc')));
      // Same installation → same record; another installation → another.
      expect(DeviceTrustService.hashInstallId('install-abc'), hash);
      expect(DeviceTrustService.hashInstallId('install-xyz'), isNot(hash));
    });
  });
}
