/// The mobile app's Help & Support FAQ — one list for farmers, one for
/// buyers, each followed by the questions both share. Every answer
/// describes what the app actually does; keep them in step with it.
library;

/// The AgriTrade+ team's support email, for the mobile app and the Admin
/// Portal.
const String kSupportEmail = 'agritrade.team@gmail.com';

class MobileFaq {
  final String question;
  final String answer;
  const MobileFaq(this.question, this.answer);
}

const List<MobileFaq> _farmerFaqs = [
  MobileFaq(
    'How do I post a product?',
    'Tap the green + button at the bottom of the screen. Choose the '
        'product name from the supported list, then add the price, available '
        'stock, a photo and how buyers can get it (pick-up or delivery), and '
        'tap Post.',
  ),
  MobileFaq(
    'Why does AgriTrade+ warn me about my price?',
    'Your price is compared with the current market average for that '
        'product. If it is much higher or lower, you are told why and can '
        'change it — or tap Post Anyway to keep it.',
  ),
  MobileFaq(
    'How do I update my stock?',
    'Open Orders, tap Inventory, then Update Stock on the product. You can '
        'also tap the ⋮ beside a product on your Profile and choose Update '
        'Quantity.',
  ),
  MobileFaq(
    'When is a product marked Low Stock?',
    'When 20% or less is left of the stock you last set. For example, if '
        'you posted 100 kg, it shows Low Stock at 20 kg. Out of Stock means '
        'none is left.',
  ),
  MobileFaq(
    'How do I accept or reject an order?',
    'Open Orders, tap Details on the order, then Accept or Reject at the '
        'bottom. Rejecting returns the quantity to your stock.',
  ),
  MobileFaq(
    'What if I cannot deliver on the agreed date?',
    'Open the confirmed order and tap Report Delay. Choose the reason and '
        'propose a new date; the buyer can accept it or cancel the order.',
  ),
  MobileFaq(
    'How can buyers find my products?',
    'Your active products appear in the marketplace. To send them to '
        'buyers yourself, open Profile › settings (gear) › Share My Store.',
  ),
  MobileFaq(
    'Why do I need approval before selling?',
    'Every farmer account is reviewed by the AgriTrade+ team first. Once '
        'it is approved, log in again to start posting products.',
  ),
];

const List<MobileFaq> _buyerFaqs = [
  MobileFaq(
    'How do I place an order?',
    'Open a product and tap Order Now. Choose the quantity, pick-up or '
        'delivery, and the date you need it, then place your order. The '
        'farmer confirms it.',
  ),
  MobileFaq(
    'Why is delivery not available to my location?',
    'Each farmer chooses the areas they deliver to. Message the farmer to '
        'ask them to add your area, or choose pick-up instead.',
  ),
  MobileFaq(
    'How do I follow my order?',
    'Open Orders. Each order shows its status — Pending, Confirmed, Shipped '
        'or Ready for Pick-up, and Completed — and tap Details for more.',
  ),
  MobileFaq(
    'I already received my order. What do I do?',
    'Open the order and tap Order Received. It completes the order, issues '
        'your receipt and lets you review the product.',
  ),
  MobileFaq(
    'The farmer proposed a new date. What do I do?',
    'Open the order: accept the new date to keep the order, or cancel it. '
        'You can also message the farmer first.',
  ),
  MobileFaq(
    'How do I review a product?',
    'Once an order is completed, tap Review on it. Reviewing your completed '
        'orders also earns you the Trusted Buyer badge.',
  ),
  MobileFaq(
    'How do I save products I like?',
    'Tap the heart on a product. You will find them again under Profile › '
        'Liked Products.',
  ),
];

const List<MobileFaq> _sharedFaqs = [
  MobileFaq(
    'How do I change my password?',
    'Open Profile › settings (gear) › Manage Account › Change Password. '
        'Enter your current password, then the new one: at least 12 '
        'characters, with an uppercase and a lowercase letter, a number and '
        'a symbol. Then enter the 6-digit code we email you. Other devices '
        'are logged out. Forgot it? Use Forgot Password on the login screen.',
  ),
  MobileFaq(
    'What is a recovery email?',
    'A second email address, different from the one you log in with, '
        'that helps you get back into your account. Add it in Edit Profile '
        'and enter the 6-digit code we send to it to verify it.',
  ),
  MobileFaq(
    'How can I contact support?',
    'Email the AgriTrade+ team at $kSupportEmail, or send a support '
        'request from this page.',
  ),
];

/// The FAQ for a farmer or a buyer, the shared questions last.
List<MobileFaq> mobileFaqsFor({required bool farmer}) => [
  ...(farmer ? _farmerFaqs : _buyerFaqs),
  ..._sharedFaqs,
];
