import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// A buyer's Liked Products: users/{uid}/savedProducts/{productId}, holding
/// only the product id and when it was liked. ("saved" is the storage name;
/// everything the buyer reads says "Liked".) The listing itself is always
/// read live from products/{productId}, so a liked product never shows a
/// stale price or stock — and one that was archived, suspended or deleted
/// simply drops out of the list.
///
/// One document per product, keyed by its id, so liking the same product
/// twice can never create a second record. Only the account's own buyer
/// can read or write this (see firestore.rules).
class SavedProductsService {
  final _db = FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? get _saved {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid).collection('savedProducts');
  }

  // Liking is a buyer feature (firestore.rules refuses it for anyone
  // else), so the heart is only offered to buyers. Looked up once per
  // signed-in account.
  static String? _roleUid;
  static Future<bool>? _isBuyer;

  Future<bool> currentUserIsBuyer() {
    final uid = _uid;
    if (uid == null) return Future.value(false);
    if (_roleUid != uid || _isBuyer == null) {
      _roleUid = uid;
      _isBuyer = _db
          .collection('users')
          .doc(uid)
          .get()
          .then((doc) => doc.data()?['role'] == 'buyer')
          .catchError((_) {
            _isBuyer = null; // try again next time
            return false;
          });
    }
    return _isBuyer!;
  }

  /// Returns null on success, or a message to show the user.
  Future<String?> setSaved(String productId, bool save) async {
    final saved = _saved;
    if (saved == null) return 'Please log in again.';
    try {
      if (save) {
        await saved.doc(productId).set({
          'productId': productId,
          'savedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await saved.doc(productId).delete();
      }
      return null;
    } catch (_) {
      return save
          ? 'Could not like this product. Please try again.'
          : 'Could not remove this product. Please try again.';
    }
  }

  /// The live listings for [ids], in the same order, leaving out any that
  /// no longer exist or are no longer on the marketplace.
  Future<List<DocumentSnapshot<Map<String, dynamic>>>> loadProducts(
    List<String> ids,
  ) async {
    final docs = await Future.wait(
      ids.map((id) => _db.collection('products').doc(id).get()),
    );
    return [
      for (final doc in docs)
        if (doc.exists &&
            doc.data()?['isArchived'] != true &&
            doc.data()?['isSuspended'] != true)
          doc,
    ];
  }
}

/// The signed-in buyer's liked product ids, shared by every screen that
/// draws a heart (Explore, Search, a farmer's public profile, Product
/// Details, Liked Products). They all listen to this one object, so liking
/// a product anywhere shows on all of them at once.
///
/// It mirrors Firestore: one live subscription to the buyer's
/// users/{uid}/savedProducts, restarted whenever the signed-in account
/// changes. A tap is applied here immediately — the heart fills before the
/// write finishes — and undone again if the write fails.
class LikedProducts extends ChangeNotifier {
  LikedProducts._();
  static final LikedProducts instance = LikedProducts._();

  final _service = SavedProductsService();

  StreamSubscription<User?>? _authSub;
  StreamSubscription? _likesSub;
  String? _uid;

  bool _canLike = false;
  bool _loaded = false;
  // What Firestore says, newest first.
  List<String> _serverIds = const [];
  // Taps still being written: product id -> liked?
  final Map<String, bool> _pending = {};

  /// Whether to offer the heart at all (a signed-in buyer).
  bool get canLike => _canLike;

  /// Whether the liked list has arrived from Firestore at least once.
  bool get loaded => _loaded;

  bool contains(String productId) =>
      _pending[productId] ?? _serverIds.contains(productId);

  /// Liked product ids, most recently liked first.
  List<String> get orderedIds => [
    for (final entry in _pending.entries)
      if (entry.value && !_serverIds.contains(entry.key)) entry.key,
    for (final id in _serverIds)
      if (_pending[id] != false) id,
  ];

  /// Starts following the signed-in account. Safe to call from every
  /// screen that shows a heart; only the first call does anything.
  void start() {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen(_onUser);
  }

  Future<void> _onUser(User? user) async {
    if (user?.uid == _uid && (_likesSub != null || user == null)) return;
    _uid = user?.uid;
    await _likesSub?.cancel();
    _likesSub = null;
    _serverIds = const [];
    _pending.clear();
    _canLike = false;
    _loaded = false;
    notifyListeners();
    if (user == null) return;

    final isBuyer = await _service.currentUserIsBuyer();
    // The account changed again while the role was being read.
    if (_uid != user.uid || !isBuyer) return;
    _canLike = true;
    notifyListeners();

    // No orderBy: every like must be in the result, including one whose
    // server timestamp hasn't been filled in yet. Sorted here instead.
    _likesSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('savedProducts')
        .snapshots()
        .listen((snap) {
          int at(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
            final savedAt = doc.data()['savedAt'];
            // Not stamped by the server yet = just now.
            return savedAt is Timestamp
                ? savedAt.millisecondsSinceEpoch
                : DateTime.now().millisecondsSinceEpoch;
          }

          final docs = [...snap.docs]..sort((a, b) => at(b).compareTo(at(a)));
          _serverIds = [for (final doc in docs) doc.id];
          _loaded = true;
          notifyListeners();
        }, onError: (_) {});
  }

  /// Likes or unlikes [productId]. Returns whether it is now liked, and an
  /// error message if the change could not be saved (in which case the
  /// heart has already gone back to what it was).
  Future<({bool liked, String? error})> toggle(String productId) async {
    final like = !contains(productId);
    _pending[productId] = like;
    notifyListeners();

    final error = await _service.setSaved(productId, like);

    _pending.remove(productId);
    if (error == null) {
      // Usually already reflected by the snapshot listener; this covers the
      // moment before it arrives.
      final has = _serverIds.contains(productId);
      if (like && !has) _serverIds = [productId, ..._serverIds];
      if (!like && has) {
        _serverIds = [
          for (final id in _serverIds)
            if (id != productId) id,
        ];
      }
    }
    notifyListeners();
    return (liked: error == null ? like : !like, error: error);
  }
}
