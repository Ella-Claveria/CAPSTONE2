import 'package:flutter/material.dart';

import '../data/legal_policies.dart';
import 'policy_document_screen.dart';

/// AgriTrade+ Privacy Policy ([kPrivacyPolicy]) — what data is collected,
/// why, who can see it and how it is protected. Kept separate from
/// TermsAndConditionsScreen (the platform's rules). Its location wording
/// matches the farmer/buyer location permission dialogs
/// (location_permission_prompt.dart) and the farmer Public Location Preview
/// (register_screen.dart) — keep them in sync.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const PolicyDocumentScreen(document: kPrivacyPolicy);
}
