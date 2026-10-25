import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/mobile_faqs.dart' show kSupportEmail;

/// The Admin Portal's Help & Support FAQ: its entries, the built-in
/// starter entries, where they are stored (`adminFaqs` in Firestore,
/// editable by administrators in FAQ Management), and the word matching
/// its search uses.

/// The support team's official email and contact number, shown at the
/// bottom of Help & Support. An empty one is not shown. Set them only to
/// details the client has confirmed.
const String kAdminSupportEmail = kSupportEmail;
const String kAdminSupportPhone = '';

/// The confirmed support channels, in the order they are shown.
List<({String label, String value})> get adminSupportContacts => [
  if (kAdminSupportEmail.trim().isNotEmpty)
    (label: 'Email', value: kAdminSupportEmail.trim()),
  if (kAdminSupportPhone.trim().isNotEmpty)
    (label: 'Phone', value: kAdminSupportPhone.trim()),
];

/// The FAQ's categories, in the order Help & Support lists them.
enum AdminFaqCategory {
  account('Account and Login'),
  users('User Management'),
  listings('Product Listings'),
  transactions('Transactions and Marketplace'),
  pricing('AI Price Recommendations'),
  security('Security and Audit Logs'),
  maintenance('System Maintenance'),
  general('General Questions');

  final String label;
  const AdminFaqCategory(this.label);

  static AdminFaqCategory fromId(String? id) => AdminFaqCategory.values
      .firstWhere((c) => c.name == id, orElse: () => AdminFaqCategory.general);
}

class AdminFaq {
  final String id;
  final AdminFaqCategory category;
  final String question;
  final String answer;

  /// Extra words the search matches on, besides the question and answer.
  final List<String> keywords;

  /// Shown in Help & Support.
  final bool published;

  /// The procedure still needs to be confirmed by an administrator or the
  /// client; shown with the answer.
  final bool needsReview;

  /// Position within its category.
  final int order;

  const AdminFaq({
    required this.id,
    required this.category,
    required this.question,
    required this.answer,
    this.keywords = const [],
    this.published = true,
    this.needsReview = false,
    this.order = 0,
  });

  factory AdminFaq.fromMap(String id, Map<String, dynamic> data) => AdminFaq(
    id: id,
    category: AdminFaqCategory.fromId(data['category']?.toString()),
    question: (data['question'] ?? '').toString(),
    answer: (data['answer'] ?? '').toString(),
    keywords: [
      for (final k in (data['keywords'] as List?) ?? const [])
        if (k.toString().trim().isNotEmpty) k.toString().trim(),
    ],
    published: data['published'] == true,
    needsReview: data['needsReview'] == true,
    order: (data['order'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'category': category.name,
    'question': question,
    'answer': answer,
    'keywords': keywords,
    'published': published,
    'needsReview': needsReview,
    'order': order,
  };

  AdminFaq copyWith({bool? published}) => AdminFaq(
    id: id,
    category: category,
    question: question,
    answer: answer,
    keywords: keywords,
    published: published ?? this.published,
    needsReview: needsReview,
    order: order,
  );
}

/// [faqs] in Help & Support's order: by category, then position.
List<AdminFaq> sortAdminFaqs(Iterable<AdminFaq> faqs) =>
    [...faqs]..sort((a, b) {
      final byCategory = a.category.index.compareTo(b.category.index);
      if (byCategory != 0) return byCategory;
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.question.compareTo(b.question);
    });

// ===================================================================
// Storage
// ===================================================================

/// `adminFaqs/{id}` — read and written only by an active Admin
/// (firestore.rules).
class AdminFaqService {
  AdminFaqService._();

  static final _faqs = FirebaseFirestore.instance.collection('adminFaqs');

  /// Every entry, published or not.
  static Stream<List<AdminFaq>> watchAll() => _faqs.snapshots().map(
    (snap) => sortAdminFaqs([
      for (final doc in snap.docs)
        refreshStaleDefault(AdminFaq.fromMap(doc.id, doc.data())),
    ]),
  );

  static Map<String, dynamic> _stamp() => {
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': FirebaseAuth.instance.currentUser?.uid,
  };

  /// Adds [faq] (its id is ignored) or saves changes to it.
  static Future<void> save(AdminFaq faq, {required bool isNew}) async {
    if (isNew) {
      await _faqs.add({
        ...faq.toMap(),
        ..._stamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _faqs.doc(faq.id).update({...faq.toMap(), ..._stamp()});
    }
  }

  static Future<void> setPublished(String id, bool published) =>
      _faqs.doc(id).update({'published': published, ..._stamp()});

  static Future<void> delete(String id) => _faqs.doc(id).delete();

  /// Saves the built-in entries ([kDefaultAdminFaqs]) that are not stored
  /// yet, so they can be edited. Never overwrites an edited one.
  static Future<int> importDefaults() async {
    final existing = (await _faqs.get()).docs.map((d) => d.id).toSet();
    final batch = FirebaseFirestore.instance.batch();
    var added = 0;
    for (final faq in kDefaultAdminFaqs) {
      if (existing.contains(faq.id)) continue;
      batch.set(_faqs.doc(faq.id), {
        ...faq.toMap(),
        ..._stamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      added++;
    }
    if (added > 0) await batch.commit();
    return added;
  }
}

// ===================================================================
// Search: the words of a question, so "password change" finds
// "How do I change my password?" and Taglish words find English ones
// ===================================================================

// Words that carry no meaning for matching (English and common Filipino).
const Set<String> _stopWords = {
  'a', 'an', 'the', 'i', 'me', 'my', 'we', 'our', 'you', 'your', 'it',
  'is', 'are', 'was', 'be', 'am', 'do', 'does', 'did', 'can', 'could',
  'should', 'would', 'will', 'how', 'what', 'when', 'where', 'who', 'why',
  'which', 'to', 'of', 'for', 'in', 'on', 'at', 'by', 'with', 'and', 'or',
  'if', 'this', 'that', 'there', 'about', 'from', 'as', 'any', 'some',
  'please', 'pls', 'hi', 'hello', 'need', 'want', 'know', 'get', 'have',
  'has', 'admin', 'administrator', 'agritrade', 'think', 'maybe', 'someone',
  'something', 'im', 'got', 'just', 'really', 'still', 'also',
  // Filipino.
  'ang', 'ng', 'sa', 'mga', 'ko', 'ba', 'po', 'na', 'yung', 'ung', 'lang',
  'paano', 'ano', 'saan', 'kailan', 'bakit', 'naman', 'mo', 'ako', 'si',
  'pag', 'kapag', 'para', 'may', 'ito', 'iyan', 'yan', 'dito',
};

// Different words for the same thing, mapped to one (after stemming).
const Map<String, String> _synonyms = {
  'ban': 'suspend',
  'block': 'suspend',
  'deactivat': 'suspend',
  'suspens': 'suspend',
  'pass': 'password',
  'pwd': 'password',
  'signin': 'login',
  'log': 'login',
  'device': 'session',
  'browser': 'session',
  'product': 'listing',
  'post': 'listing',
  'produkto': 'listing',
  'complaint': 'report',
  'flag': 'report',
  'ireport': 'report',
  'pay': 'payment',
  'gcash': 'payment',
  'bayad': 'payment',
  'magbayad': 'payment',
  'presyo': 'price',
  'pric': 'price',
  'suggest': 'recommend',
  'recommendation': 'recommend',
  'hack': 'unauthorized',
  'breach': 'unauthorized',
  'downtime': 'maintenance',
  'palitan': 'change',
  'baguhin': 'change',
  'reset': 'change',
  'policy': 'terms',
  'privacy': 'terms',
  'help': 'support',
  'contact': 'support',
};

String _stem(String word) {
  for (final suffix in ['ing', 'ed', 'es', 's']) {
    if (word.length > suffix.length + 3 && word.endsWith(suffix)) {
      return word.substring(0, word.length - suffix.length);
    }
  }
  return word;
}

/// The meaningful words of [text], in one form each.
Set<String> adminFaqTerms(String text) {
  final words = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'));
  final terms = <String>{};
  for (final word in words) {
    if (word.isEmpty || _stopWords.contains(word)) continue;
    final stem = _stem(word);
    terms.add(_synonyms[word] ?? _synonyms[stem] ?? stem);
  }
  return terms;
}

// ===================================================================
// Built-in entries
// ===================================================================

/// The starter FAQ, written from how the Admin Portal works today. Shown
/// while the database has no FAQs; FAQ Management saves them there the
/// first time it is opened, and they can then be edited. Entries marked [needsReview]
/// describe a procedure or policy that is not settled in the system yet.
const List<AdminFaq> kDefaultAdminFaqs = [
  // ---- Account and Login ----
  AdminFaq(
    id: 'default-account-password',
    category: AdminFaqCategory.account,
    order: 1,
    question: 'How do I change my password?',
    keywords: ['password', 'change password', 'new password'],
    answer:
        'Open your account at the bottom of the sidebar, then Manage '
        'Account › Change Password. Enter your current password and the new '
        'one: at least 12 characters, with an uppercase and a lowercase '
        'letter, a number and a symbol. Then enter the 6-digit code emailed '
        'to you; every other device is logged out. If you have forgotten '
        'your password, use Forgot Password on the Admin login page instead.',
  ),
  AdminFaq(
    id: 'default-account-cannot-login',
    category: AdminFaqCategory.account,
    order: 2,
    question: 'What should I do if I cannot log in?',
    keywords: ['cannot login', 'login', 'locked', 'forgot', 'login failed'],
    answer:
        'Check that your email and password are typed correctly. After 5 '
        'wrong passwords in a row, login is paused for 5 minutes — wait and '
        'try again. If you forgot your password, use Forgot Password on the '
        'login page to get a reset email. If the portal says the account is '
        'already logged in on another device, you can continue and sign the '
        'other session out. If you still cannot log in, contact support.',
  ),
  AdminFaq(
    id: 'default-account-sessions',
    category: AdminFaqCategory.account,
    order: 3,
    question: 'How do I review active sessions?',
    keywords: ['session', 'active session', 'device', 'signed in'],
    answer:
        'Open your account at the bottom of the sidebar, then Manage '
        'Account › Active Sessions › View. It lists this device, any other '
        'session still signed in, and recent sessions that have ended, with '
        'the browser, approximate location and when each was last active.',
  ),
  AdminFaq(
    id: 'default-account-unfamiliar-session',
    category: AdminFaqCategory.account,
    order: 4,
    question: 'What should I do if I notice an unfamiliar session?',
    keywords: ['unfamiliar', 'unknown session', 'strange device', 'session'],
    answer:
        'In Active Sessions, choose Revoke Session on it and confirm with your '
        'password: that device is signed out at once. Then change your '
        'password, check Audit Log › Login Activity for anything you did not '
        'do, and report it to support.',
  ),

  // ---- User Management ----
  AdminFaq(
    id: 'default-users-review',
    category: AdminFaqCategory.users,
    order: 1,
    question: 'How do I review user accounts?',
    keywords: ['user account', 'review account', 'farmer', 'buyer', 'account'],
    answer:
        'Open User Accounts in the sidebar. Farmers lists approved farmers '
        'with their RSBA No., barangay, listings and completed orders; Buyers '
        'lists buyer accounts with their email, moderation and account '
        'status. View account opens an account\'s details and moderation '
        'history. Farmers waiting for approval are in Verification.',
  ),
  AdminFaq(
    id: 'default-users-when-suspend',
    category: AdminFaqCategory.users,
    order: 2,
    needsReview: true,
    question: 'When should an account be suspended?',
    keywords: ['suspend', 'suspension', 'when suspend'],
    answer:
        'Suspend an account when its reports show a real violation — for '
        'example fraud, abusive messages or misleading listings — and a '
        'warning is not enough. Suspend Accounts flags accounts with 10 or '
        'more reports, but the number of reports alone is not proof. The '
        'exact rules for when to suspend are still to be confirmed by the '
        'client.',
  ),
  AdminFaq(
    id: 'default-users-before-suspend',
    category: AdminFaqCategory.users,
    order: 3,
    question: 'What should I check before suspending an account?',
    keywords: ['before suspend', 'check suspend', 'suspend'],
    answer:
        'Read the reports against the account and its moderation history '
        '(View account), and check whether it has already been warned. '
        'Suspend from Suspend Accounts in your account menu: you must give a '
        'reason, which the user is shown, and choose how long — 24 hours, 3, '
        '7 or 30 days, a custom length, or until reactivated. Choose the '
        'shortest that addresses the problem.',
  ),
  AdminFaq(
    id: 'default-users-reported-user',
    category: AdminFaqCategory.users,
    order: 4,
    question: 'How do I handle a reported user?',
    keywords: ['reported user', 'report', 'moderation'],
    answer:
        'Open Moderation Queue › Pending Reports and choose Start Review on '
        'the report. When you have looked into it, close it with Dismiss '
        'Report, Resolve with No Violation, or Confirm Violation. Confirm '
        'Violation offers the actions that fit the report: record it only, '
        'warn, remove a review, hide a listing, or suspend or ban the '
        'account. Every action is recorded in the Audit Log.',
  ),

  // ---- Product Listings ----
  AdminFaq(
    id: 'default-listings-review',
    category: AdminFaqCategory.listings,
    order: 1,
    question: 'How do I review a product listing?',
    keywords: ['listing', 'review listing', 'product'],
    answer:
        'Listings are reviewed through reports: a report about a listing '
        'shows the Related Listing in the Moderation Queue. Prices are not '
        'reviewed: a farmer sets their own, and buyers decide whether to buy. '
        'The portal has no separate page that lists every listing.',
  ),
  AdminFaq(
    id: 'default-listings-misleading',
    category: AdminFaqCategory.listings,
    order: 2,
    question: 'What should I do if a listing contains misleading information?',
    keywords: ['misleading', 'fake listing', 'wrong information', 'listing'],
    answer:
        'Open its report and choose Confirm Violation, then Hide Related '
        'Listing (and a warning, if it fits). The listing is hidden from the '
        'marketplace, not deleted. If it was a mistake, open the report and '
        'choose Restore listing.',
  ),
  AdminFaq(
    id: 'default-listings-reported',
    category: AdminFaqCategory.listings,
    order: 3,
    question: 'How do I respond to a reported listing?',
    keywords: ['reported listing', 'listing report', 'report'],
    answer:
        'In Moderation Queue, filter by target Listing. Start Review, check '
        'the Related Listing and the reason given, then Dismiss Report, '
        'Resolve with No Violation, or Confirm Violation and hide the listing '
        'or warn the farmer.',
  ),

  // ---- Transactions and Marketplace ----
  AdminFaq(
    id: 'default-transactions-review',
    category: AdminFaqCategory.transactions,
    order: 1,
    question: 'How can I review transaction-related information?',
    keywords: ['transaction', 'order', 'sales', 'report'],
    answer:
        'The Analytics Dashboard shows transactions in summary — Total '
        'Transaction Value, Sales Performance and the other charts — and '
        'Export Report saves them as a PDF or Excel report. User Accounts › '
        'Farmers shows each farmer\'s completed orders. The portal has no '
        'page for individual orders.',
  ),
  AdminFaq(
    id: 'default-transactions-problem',
    category: AdminFaqCategory.transactions,
    order: 2,
    needsReview: true,
    question: 'What should I do if a buyer or seller reports a problem?',
    keywords: ['problem', 'complaint', 'issue', 'buyer', 'seller', 'report'],
    answer:
        'Reports that buyers and farmers send from the app arrive in the '
        'Moderation Queue; handle them there. Support requests that buyers '
        'send from the app are stored, but the Admin Portal does not show '
        'them yet — how those are answered still needs to be confirmed.',
  ),
  AdminFaq(
    id: 'default-transactions-payments',
    category: AdminFaqCategory.transactions,
    order: 3,
    question: 'Does AgriTrade+ directly process payments?',
    keywords: ['payment', 'pay', 'gcash', 'cash', 'money'],
    answer:
        'No. AgriTrade+ connects buyers and farmers and records orders, but '
        'it does not process or hold payments. Payment is settled directly '
        'between the buyer and the farmer. The receipt in the app is a record '
        'of the order, not proof of payment.',
  ),

  // ---- AI Price Recommendations ----
  AdminFaq(
    id: 'default-pricing-what',
    category: AdminFaqCategory.pricing,
    order: 1,
    question: 'What are AI-driven price recommendations?',
    keywords: ['ai', 'price recommendation', 'suggested price', 'price'],
    answer:
        'When a farmer lists a product, the app suggests a price, labelled '
        '"AI-Assisted Price Recommendation". It is calculated with fixed '
        'rules — a weighted middle value — from the reference prices in Price '
        'Management, similar active listings and completed sales, and is '
        'labelled Limited, Moderate or Strong by how much data supports it.',
  ),
  AdminFaq(
    id: 'default-pricing-guaranteed',
    category: AdminFaqCategory.pricing,
    order: 2,
    question: 'Are recommended prices guaranteed?',
    keywords: ['guaranteed', 'guarantee', 'accurate', 'price'],
    answer:
        'No. A recommended price is an estimate from the data available. It '
        'is not a guaranteed market price or transaction price, and it can be '
        'off when little data exists. Farmers set their own prices.',
  ),
  AdminFaq(
    id: 'default-pricing-explain',
    category: AdminFaqCategory.pricing,
    order: 3,
    question: 'What should I explain when users question a suggested price?',
    keywords: ['question price', 'wrong price', 'explain price', 'price'],
    answer:
        'Explain that the suggestion is an estimate from reference prices, '
        'similar listings and past sales, and that its label shows how much '
        'data was behind it. The farmer decides the final price. If the '
        'reference price for that commodity is out of date, update it in '
        'Price Management.',
  ),

  // ---- Security and Audit Logs ----
  AdminFaq(
    id: 'default-security-login-activity',
    category: AdminFaqCategory.security,
    order: 1,
    question: 'How do I review login activity?',
    keywords: ['login activity', 'audit', 'login history', 'sign in'],
    answer:
        'Open Audit Log › Login Activity, or Manage Account › Login '
        'Activity › View. It lists successful and failed logins, logouts, '
        'new-device logins and sessions that were ended or revoked, with the '
        'device, IP address and approximate location.',
  ),
  AdminFaq(
    id: 'default-security-why-document',
    category: AdminFaqCategory.security,
    order: 2,
    question: 'Why should administrative actions be documented?',
    keywords: ['document', 'audit', 'accountability', 'record'],
    answer:
        'So every decision can be checked and explained later. The Audit Log '
        'records administrative actions automatically — approvals, price '
        'changes, moderation, suspensions, exports and announcements — with '
        'who did it and when. Give clear reasons where asked, because they '
        'are part of that record.',
  ),
  AdminFaq(
    id: 'default-security-unauthorized',
    category: AdminFaqCategory.security,
    order: 3,
    question: 'What should I do if I suspect unauthorized access?',
    keywords: ['unauthorized', 'hacked', 'suspicious', 'access', 'breach'],
    answer:
        'Act at once: revoke any session you do not recognize (Manage '
        'Account › Active Sessions), change your password, review Audit '
        'Log › Login Activity and recent admin actions, and report it to '
        'support with what you found.',
  ),
  AdminFaq(
    id: 'default-security-revoke',
    category: AdminFaqCategory.security,
    order: 4,
    question: 'How do I revoke an unfamiliar session?',
    keywords: ['revoke', 'sign out device', 'session', 'remove device'],
    answer:
        'Manage Account › Active Sessions › View. Under Other active '
        'sessions, choose Revoke Session, enter your password and confirm. '
        'The device loses access immediately, and the revocation is recorded '
        'in the Audit Log. Your own session cannot be revoked there — use '
        'Logout.',
  ),

  // ---- System Maintenance ----
  AdminFaq(
    id: 'default-maintenance-when',
    category: AdminFaqCategory.maintenance,
    order: 1,
    needsReview: true,
    question: 'When should system maintenance be performed?',
    keywords: ['maintenance', 'schedule', 'when maintenance'],
    answer:
        'Plan it for a time when few farmers and buyers use the app, and '
        'announce it in advance with System Maintenance in your account '
        'menu. The schedule and how far ahead to announce it are still to be '
        'agreed with the client.',
  ),
  AdminFaq(
    id: 'default-maintenance-precautions',
    category: AdminFaqCategory.maintenance,
    order: 2,
    needsReview: true,
    question:
        'What precautions should be taken before enabling maintenance mode?',
    keywords: ['maintenance mode', 'precaution', 'maintenance'],
    answer:
        'AgriTrade+ has no maintenance mode that takes the app offline. '
        'System Maintenance sends farmers and buyers a notice with the '
        'maintenance window. Send it early, make sure the start and end '
        'times are right, and avoid making changes during busy hours. A '
        'full maintenance procedure still needs to be confirmed.',
  ),
  AdminFaq(
    id: 'default-maintenance-report-issue',
    category: AdminFaqCategory.maintenance,
    order: 3,
    question: 'How should technical issues be reported?',
    keywords: ['technical issue', 'bug', 'error', 'problem', 'not working'],
    answer:
        'Write down what you were doing, the page, the time, and any message '
        'shown, and take a screenshot. Then send it to the support team, '
        'using the contact details at the bottom of Help & Support.',
  ),

  // ---- General Questions ----
  AdminFaq(
    id: 'default-general-what',
    category: AdminFaqCategory.general,
    order: 1,
    question: 'What is AgriTrade+?',
    keywords: ['agritrade', 'what is', 'platform', 'about'],
    answer:
        'AgriTrade+ is a marketplace that connects farmers in Laurel, '
        'Batangas with buyers. Farmers list supported products, buyers order '
        'and message them, and administrators verify farmers, manage '
        'reference prices and moderate the platform from this Admin Portal.',
  ),
  AdminFaq(
    id: 'default-general-who',
    category: AdminFaqCategory.general,
    order: 2,
    question: 'Who can use the platform?',
    keywords: ['who', 'users', 'roles', 'register', 'farmer', 'buyer'],
    answer:
        'Farmers (including livestock raisers), whose accounts an '
        'administrator approves before they can list products; buyers, once '
        'their email is verified; and administrators, an internal role that '
        'cannot be registered publicly.',
  ),
  AdminFaq(
    id: 'default-general-terms',
    category: AdminFaqCategory.general,
    order: 3,
    question: 'Where can I find the Terms of Service and Privacy Policy?',
    keywords: ['terms', 'privacy', 'policy', 'terms of service'],
    answer:
        'In your account menu at the bottom of the sidebar, choose Terms & '
        'Privacy. It has the Terms of Service, the Privacy Policy and the '
        'Administrator Guidelines. Farmers and buyers see the first two when '
        'they register.',
  ),
  AdminFaq(
    id: 'default-general-contact',
    category: AdminFaqCategory.general,
    order: 4,
    question: 'How can I contact support?',
    keywords: ['contact support', 'support', 'email', 'phone', 'help'],
    answer:
        'Email the AgriTrade+ team at $kSupportEmail. The address is also '
        'at the bottom of Help & Support (account menu › Help & Support), '
        'with a Copy button.',
  ),
];

/// The earlier wording of built-in answers that have since changed, by
/// id. A stored copy still holding one exactly (imported before the
/// change and never edited by an admin) shows the current wording; an
/// edited answer is left as the admin wrote it.
const Map<String, List<String>> _previousDefaultAnswers = {
  'default-account-password': [
    'Open your account at the bottom of the sidebar, then Manage '
        'Account › Change Password. Enter your current password and the new '
        'one (at least 6 characters). If you have forgotten your password, '
        'use Forgot Password on the Admin login page instead.',
    'Open your account at the bottom of the sidebar, then Manage '
        'Account › Change Password. Enter your current password and the new '
        'one: at least 12 characters, with an uppercase and a lowercase '
        'letter, a number and a symbol. If you have forgotten your password, '
        'use Forgot Password on the Admin login page instead.',
  ],
  'default-general-contact': [
    "The support team's official email and contact number are shown at "
        'the bottom of Help & Support (account menu › Help & Support), with '
        'a Copy button each, once the client has confirmed them.',
  ],
};

/// [faq], with a built-in answer's current wording when it still holds
/// the earlier one word for word (see [_previousDefaultAnswers]).
AdminFaq refreshStaleDefault(AdminFaq faq) {
  final old = _previousDefaultAnswers[faq.id];
  if (old == null || !old.contains(faq.answer.trim())) return faq;
  for (final current in kDefaultAdminFaqs) {
    if (current.id == faq.id) {
      return AdminFaq(
        id: faq.id,
        category: faq.category,
        question: faq.question,
        answer: current.answer,
        keywords: faq.keywords,
        published: faq.published,
        needsReview: faq.needsReview,
        order: faq.order,
      );
    }
  }
  return faq;
}
