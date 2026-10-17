import 'package:flutter/material.dart';

import '../data/legal_policies.dart';
import 'policy_document_screen.dart';

/// AgriTrade+ Terms of Service ([kTermsOfService]) — the rules for using
/// the platform. Opened from the registration consent checkbox and from
/// Settings/Help. Kept separate from PrivacyPolicyScreen, which covers what
/// data is collected and how it is used.
class TermsAndConditionsScreen extends StatelessWidget {
  const TermsAndConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const PolicyDocumentScreen(document: kTermsOfService);
}
