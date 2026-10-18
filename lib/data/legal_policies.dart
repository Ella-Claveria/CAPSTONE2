/// AgriTrade+'s Terms of Service, Privacy Policy and Administrator
/// Guidelines: the text alone, kept apart from the screens that show it.
///
/// The mobile app's registration screens (TermsAndConditionsScreen,
/// PrivacyPolicyScreen) and the Admin Portal's Terms & Privacy show the same
/// [kTermsOfService] and [kPrivacyPolicy], so the two can never say
/// different things. [kAdminGuidelines] is for administrators only and is
/// shown only in the Admin Portal.
///
/// DRAFT FOR THE CAPSTONE PROJECT. This text describes how AgriTrade+ works
/// as built, and must be reviewed against the system's actual behaviour and
/// applicable Philippine data privacy requirements (Republic Act No. 10173
/// and NPC issuances) before production use. Text in [square brackets] is a
/// placeholder for a detail that still needs approval (the retention periods
/// and the policies' dates); nothing here names an officer, address or date
/// that has not been given. The operator and contact are the AgriTrade+ Team
/// and its support email.
library;

import 'mobile_faqs.dart' show kSupportEmail;

/// One numbered part of a policy: optional paragraphs, then optional
/// points.
class PolicySection {
  final String heading;
  final List<String> paragraphs;
  final List<String> points;

  const PolicySection(
    this.heading, {
    this.paragraphs = const [],
    this.points = const [],
  });
}

class PolicyDocument {
  final String title;

  /// Stored with a user's acceptance (users/{uid}.termsVersion and
  /// .privacyVersion), so a later change can tell who agreed to which text.
  /// Change it whenever the text changes materially.
  final String version;

  /// Null until the policy is approved; shown as a placeholder meanwhile.
  final String? effectiveDate;
  final String? lastUpdated;
  final String intro;
  final List<PolicySection> sections;

  const PolicyDocument({
    required this.title,
    required this.version,
    required this.intro,
    required this.sections,
    this.effectiveDate,
    this.lastUpdated,
  });

  /// "Effective: [to be set when approved]".
  String get effectiveLabel =>
      'Effective: ${effectiveDate ?? '[to be set when the policy is approved]'}';
  String get updatedLabel =>
      'Last updated: ${lastUpdated ?? '[to be set when the policy is approved]'}';
}

/// Who runs AgriTrade+ and how to reach them about these policies — the
/// AgriTrade+ team and its support email (data/mobile_faqs.dart).
const String kPolicyOperator = 'the AgriTrade+ Team';
const String kPolicyContact = 'the AgriTrade+ Team at $kSupportEmail';
const String kPolicyPrivacyOfficer =
    'the AgriTrade+ Team (privacy contact) at $kSupportEmail';

// ===================================================================
// TERMS OF SERVICE
// ===================================================================

const PolicyDocument kTermsOfService = PolicyDocument(
  title: 'Terms of Service',
  version: 'tos-draft-1',
  intro:
      'These Terms govern the use of AgriTrade+, a marketplace that connects '
      'farmers in Laurel, Batangas with buyers, operated by $kPolicyOperator. '
      'Please read them before creating an account.',
  sections: [
    PolicySection(
      '1. Acceptance of Terms',
      paragraphs: [
        'By creating an AgriTrade+ account and ticking the agreement box at '
            'registration, you agree to these Terms and to the Privacy '
            'Policy. If you do not agree, do not create an account.',
        'Your agreement, the version of these Terms you agreed to, and when '
            'you agreed are recorded with your account.',
      ],
    ),
    PolicySection(
      '2. User Accounts and Responsibilities',
      points: [
        'Give accurate information when you register and keep it up to date.',
        'Verify your email address with the code AgriTrade+ sends you.',
        'Keep your password private; you are responsible for activity on '
            'your account.',
        'Do not create accounts for someone else or share your account.',
        'An account is signed out automatically after a long period without '
            'use.',
      ],
    ),
    PolicySection(
      '3. User Roles',
      points: [
        'Farmer — sells supported agricultural products, including '
            'livestock raisers selling supported livestock. A farmer account '
            'is reviewed by an administrator (including the farmer '
            'credentials submitted) before it can list products.',
        'Buyer — browses listings, places orders and contacts farmers. A '
            'buyer account can be used once its email is verified.',
        'Administrator — an internal role for the operating office. It '
            'cannot be registered publicly. Administrators review farmer '
            'applications, manage reference prices, review reports and '
            'moderate the platform.',
      ],
    ),
    PolicySection(
      '4. Product Listings and Accurate Pricing',
      points: [
        'Only commodities in AgriTrade+\'s Supported Products list can be '
            'listed. The list may change as the system scope is updated.',
        'Listings must describe the product truthfully, including its '
            'quantity, unit, quality and photos.',
        'Prices must be the price you actually intend to sell at. Keep '
            'stock and availability up to date.',
        'Listings that break these Terms may be hidden or removed.',
      ],
    ),
    PolicySection(
      '5. Buyer–Seller Communication and Transactions',
      points: [
        'Buyers and farmers communicate through AgriTrade+\'s in-app '
            'messaging. Messages may include photos and, only when you choose '
            'to send it, your current location.',
        'A farmer accepts or declines each order. Pick-up or delivery is '
            'arranged between the buyer and the farmer.',
        'AgriTrade+ does not process or hold payments. Payment is settled '
            'directly between the buyer and the farmer; the receipt in the '
            'app is a record of the order, not proof of payment.',
        'AgriTrade+ is not a party to the sale and does not guarantee the '
            'quality, delivery or payment of any order.',
      ],
    ),
    PolicySection(
      '6. AI-Assisted Price Recommendations and Their Limitations',
      paragraphs: [
        'When a farmer lists a product, AgriTrade+ may suggest a price. The '
            'suggestion is calculated from the reference prices set by the '
            'administrators, the prices of similar active listings, '
            'completed sales recorded in AgriTrade+ and demand activity, and '
            'is labelled with how much data supports it.',
        'Suggested prices, market trends and forecasts are informational '
            'estimates only. They do not guarantee actual market prices, a '
            'sale, or any transaction outcome, and they may be inaccurate '
            'when little data is available. Farmers set their own prices and '
            'remain responsible for them.',
      ],
    ),
    PolicySection(
      '7. Prohibited Activities',
      points: [
        'Fraud, scams, or fake or misleading listings.',
        'Listing products outside the Supported Products list, or products '
            'you do not have.',
        'Harassment, threats, abusive or offensive messages.',
        'Using another person\'s identity or documents.',
        'Attempting to access other accounts, data or administrative '
            'functions, or to interfere with the system.',
        'Using AgriTrade+ for anything unlawful.',
      ],
    ),
    PolicySection(
      '8. Reports, Account Restrictions and Suspension',
      points: [
        'Users can report listings, messages, reviews and other users. '
            'Administrators review reports and may issue warnings, hide or '
            'remove listings or reviews, and suspend or ban accounts.',
        'A suspension may last for a set time or until an administrator '
            'reactivates the account. You are told the reason and, for a '
            'timed suspension, when it ends. A suspended account cannot log '
            'in; its orders, listings and reports are kept.',
        'A ban (deactivation) is for serious or repeated violations.',
        'If you believe a decision is wrong, contact $kPolicyContact.',
      ],
    ),
    PolicySection(
      '9. System Availability and Maintenance',
      points: [
        'AgriTrade+ needs an internet connection for most functions.',
        'It may be unavailable at times for maintenance, network problems or '
            'technical issues. Planned maintenance may be announced in the '
            'app.',
        'AgriTrade+ is provided as it is, without a guarantee that it will '
            'always be available or free of errors.',
      ],
    ),
    PolicySection(
      '10. Changes to These Terms',
      paragraphs: [
        'These Terms may be updated. When a change is significant, you will '
            'be told in the app and may be asked to agree to the new version '
            'before you continue. The version and dates are shown at the top '
            'of this page.',
      ],
    ),
    PolicySection(
      '11. Contact',
      paragraphs: ['Questions about these Terms: $kPolicyContact.'],
    ),
  ],
);

// ===================================================================
// PRIVACY POLICY
// ===================================================================

const PolicyDocument kPrivacyPolicy = PolicyDocument(
  title: 'Privacy Policy',
  version: 'privacy-draft-1',
  intro:
      'This Privacy Policy explains what personal information AgriTrade+ '
      'collects, why, who can see it, and how it is protected. AgriTrade+ is '
      'operated by $kPolicyOperator.',
  sections: [
    PolicySection(
      '1. Personal Information Collected',
      points: [
        'Account details: name, email address, mobile number, role, profile '
            'photo, and your password (kept by Google Firebase '
            'Authentication, never stored by AgriTrade+ in readable form). '
            'If you sign in with Google, the name, email and photo of your '
            'Google account.',
        'Farmer verification: barangay, RSBSA number and the credential '
            'documents you upload for review.',
        'Location: your barangay, municipality and province, and — when you '
            'allow it — the precise coordinates of your farm or your '
            'location.',
        'Marketplace activity: listings, orders, receipts, reviews, saved '
            'products, reports and support requests.',
        'Messages: conversation messages, photos and any location you '
            'choose to share in a conversation, plus whether you are online '
            'or typing.',
        'Search activity: what you search for in the marketplace.',
        'Devices and notifications: a notification token for your device, '
            'and a record of each device that has signed in to your account '
            '(its device name, platform and app version), used for new-'
            'device sign-in alerts.',
        'Security records: failed login attempts are counted against a '
            'one-way scrambled form of the email address, to pause repeated '
            'wrong passwords.',
      ],
    ),
    PolicySection(
      '2. Why It Is Collected',
      points: [
        'To create your account, verify your email and keep you signed in.',
        'To review farmer applications.',
        'To show listings, process orders and issue receipts.',
        'To deliver messages and notifications.',
        'To provide location-based features such as nearby products and '
            'distances.',
        'To calculate price suggestions and market analytics (section 6).',
        'To keep the platform safe: reports, moderation, suspensions and '
            'security records.',
      ],
    ),
    PolicySection(
      '3. What Other Users Can See',
      points: [
        'Farmers: your name, profile photo, barangay, municipality and '
            'province, your listings, and your ratings and reviews.',
        'Buyers: your name and profile photo, to the farmers you interact '
            'with, and the reviews you write.',
        'Your email address, mobile number, RSBSA number and verification '
            'documents are not shown to other users.',
      ],
    ),
    PolicySection(
      '4. Location and Map Data',
      points: [
        'Your precise coordinates are kept in a private part of your '
            'account that only you and the administrators can read.',
        'The marketplace map shows farms by barangay, as an average '
            'location of the farmers there, never a farmer\'s exact pin.',
        'When an order is confirmed, the farm location needed for pick-up is '
            'shared with that order\'s buyer.',
        'Administrators see buyer demand on a heat map built from orders, '
            'grouped by area.',
        'Addresses are looked up from coordinates using Google Maps and '
            'OpenStreetMap.',
      ],
    ),
    PolicySection(
      '5. Messages and Transactions',
      points: [
        'Messages can be read only by the two people in the conversation. '
            'Administrators cannot open conversations; when you report a '
            'user from a conversation, the report contains the reason and '
            'description you write.',
        'Order details and receipts are visible to that order\'s buyer and '
            'farmer, and to administrators.',
      ],
    ),
    PolicySection(
      '6. AI and Analytics',
      paragraphs: [
        'Price suggestions, market trends and demand analytics are '
            'calculated from marketplace data: reference prices, listings, '
            'completed sales, searches and orders. They are used in '
            'aggregated form — by commodity, period and area — and are not '
            'used to make decisions about you as a person.',
        'Administrators can export reports of this aggregated data.',
      ],
    ),
    PolicySection(
      '7. Data Sharing and Service Providers',
      paragraphs: [
        'AgriTrade+ does not sell personal information. It is processed by '
            'these service providers to run the app:',
      ],
      points: [
        'Google Firebase — sign-in, database, server functions, push '
            'notifications and web hosting.',
        'Cloudinary — storage of uploaded photos and documents.',
        'Google Maps Platform and OpenStreetMap — maps and address lookup.',
        'Gmail — sending verification codes and account emails.',
      ],
    ),
    PolicySection(
      '8. Security Safeguards',
      points: [
        'Connections to AgriTrade+ and its providers use encrypted HTTPS.',
        'Database access rules limit each account to the data it is allowed '
            'to see; private details and exact locations are restricted.',
        'Email verification codes, and a pause after 5 wrong passwords.',
        'Administrator accounts have one active session at a time, sign-in '
            'alerts, and an audit log of administrative actions.',
        'No system is completely secure. Report a suspected problem to '
            '$kPolicyContact.',
      ],
    ),
    PolicySection(
      '9. Data Retention and Deletion',
      paragraphs: [
        'Your information is kept while your account exists. Suspending or '
            'banning an account does not delete its orders, listings, '
            'reports or reviews, so that records stay complete.',
        'AgriTrade+ does not yet offer deleting an account from inside the '
            'app. To ask for your account and personal information to be '
            'deleted, contact $kPolicyContact. Some records may need to be '
            'kept where required by law or to resolve a dispute.',
        '[Retention periods for each kind of record — to be approved.]',
      ],
    ),
    PolicySection(
      '10. Your Rights and Privacy Inquiries',
      paragraphs: [
        'Under the Philippine Data Privacy Act of 2012 (Republic Act No. '
            '10173), you may have the right to be informed, to access, to '
            'correct, to object, to erasure or blocking, to data '
            'portability, to file a complaint, and to damages.',
        'You can correct most of your details in your profile. For other '
            'requests or questions, contact $kPolicyPrivacyOfficer.',
        'This policy describes how AgriTrade+ is designed to handle personal '
            'information; it is not a legal guarantee of compliance.',
      ],
    ),
    PolicySection(
      '11. Updates to This Policy and Contact',
      paragraphs: [
        'This policy may be updated. Significant changes will be announced '
            'in the app. The version and dates are shown at the top of this '
            'page.',
        'Contact: $kPolicyContact.',
      ],
    ),
  ],
);

// ===================================================================
// ADMINISTRATOR GUIDELINES (Admin Portal only)
// ===================================================================

const PolicyDocument kAdminGuidelines = PolicyDocument(
  title: 'Administrator Guidelines',
  version: 'admin-guidelines-draft-1',
  intro:
      'Internal guidelines for administrators of the AgriTrade+ Admin '
      'Portal. They are not part of the public Terms of Service, and apply in '
      'addition to them.',
  sections: [
    PolicySection(
      '1. Access for Legitimate Purposes Only',
      points: [
        'Open user accounts, verification documents, orders and locations '
            'only when your work requires it: reviewing an '
            'application, a report, an order issue or a support request.',
        'Do not look up people out of curiosity or for personal reasons.',
      ],
    ),
    PolicySection(
      '2. Confidentiality of Personal Information',
      points: [
        'Treat everything in the portal as confidential, including what you '
            'see in exports and screenshots.',
        'Keep exported reports only as long as needed, and store them where '
            'only authorized people can open them.',
        'Buyer email addresses are partly hidden in the portal on purpose; '
            'do not try to work them out.',
      ],
    ),
    PolicySection(
      '3. Responsible Use of Moderation and Suspension',
      points: [
        'Decide on the facts in the report and the account\'s history, not '
            'on who the person is.',
        'Always give a clear, factual reason; the user is shown it.',
        'Use the shortest suspension that addresses the problem; reserve '
            'bans for serious or repeated violations.',
        'Reactivate an account promptly once a mistake is found.',
      ],
    ),
    PolicySection(
      '4. No Unauthorized Disclosure or Misuse',
      points: [
        'Never share a user\'s personal information with anyone outside the '
            'authorized team, or use it for anything other than running '
            'AgriTrade+.',
        'Send farmer or buyer information to a third party only with proper '
            'authorization and a lawful basis.',
      ],
    ),
    PolicySection(
      '5. Protecting Administrator Credentials and Sessions',
      points: [
        'Use a strong password that you do not use anywhere else, and never '
            'share it or your account.',
        'Log out on shared computers. Check Manage Account › Active '
            'Sessions, and sign out any device you do not recognize.',
        'A sign-in alert you did not expect means someone may know your '
            'password: change it at once and report it.',
      ],
    ),
    PolicySection(
      '6. Reviewing Audit Logs',
      points: [
        'The Audit Log records administrative actions, with the device, IP '
            'address and approximate location. Review it only for authorized '
            'operational, security or accountability purposes.',
        'Do not use it to monitor colleagues for unrelated reasons.',
      ],
    ),
    PolicySection(
      '7. Reporting Security Incidents',
      paragraphs: [
        'Report at once — to $kPolicyContact — any suspected breach, lost '
            'device, unknown session, leaked export, or misuse of the '
            'portal. Under the Data Privacy Act, some breaches must be '
            'reported to the National Privacy Commission within a set time, '
            'so do not wait.',
      ],
    ),
    PolicySection(
      '8. Following Policies',
      paragraphs: [
        'Follow these guidelines, the Terms of Service, the Privacy Policy, '
            'the Philippine Data Privacy Act of 2012 and the operating '
            'office\'s own rules. [Internal policy references — to be '
            'approved.]',
      ],
    ),
  ],
);
