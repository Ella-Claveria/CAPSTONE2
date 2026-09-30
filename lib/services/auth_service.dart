import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'push_notification_service.dart';

/// What happened when the user tapped "Continue with Google".
enum GoogleSignInOutcome { signedIn, needsProfile, cancelled, error }

/// Result of [AuthService.signInWithGoogle] — [needsProfile] means this
/// Google account authenticated successfully but has no users/{uid}
/// Firestore document yet (a brand-new sign-in), so the caller should send
/// them to pick a role (and, for farmers, barangay + certificate) instead
/// of routing them straight into the app.
class GoogleSignInResult {
  final GoogleSignInOutcome outcome;
  final String? uid;
  final String? email;
  final String? displayName;
  final String? message;

  const GoogleSignInResult._(
    this.outcome, {
    this.uid,
    this.email,
    this.displayName,
    this.message,
  });

  const GoogleSignInResult.signedIn(String uid) : this._(GoogleSignInOutcome.signedIn, uid: uid);

  const GoogleSignInResult.needsProfile({
    required String uid,
    required String? email,
    required String? displayName,
  }) : this._(GoogleSignInOutcome.needsProfile, uid: uid, email: email, displayName: displayName);

  const GoogleSignInResult.cancelled() : this._(GoogleSignInOutcome.cancelled);

  const GoogleSignInResult.error(String message) : this._(GoogleSignInOutcome.error, message: message);
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _users = FirebaseFirestore.instance.collection('users');
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleSignInReady = false;

  // The signed-in user's UID, or null if nobody's logged in.
  String? get currentUid => _auth.currentUser?.uid;

  // Create an account with a role ('farmer' or 'buyer').
  Future<String?> signUp({
    required String fullName,
    required String email,
    required String password,
    required String role,
    // Registration's consent checkbox already gates whether this method is
    // ever called (see RegisterScreen._isFormValid) — recorded here purely
    // as an audit trail of what the user agreed to. supportedProductsAcknowledged
    // is Farmer-only (see RegisterScreen's Supported Products section).
    bool supportedProductsAcknowledged = false,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      await cred.user?.updateDisplayName(fullName.trim());
      await _users.doc(cred.user!.uid).set({
        // 'fullName' is kept for backward compatibility with older reads;
        // 'name' is the standardized display-name field going forward
        // (matches what EditProfileScreen writes on later edits — see
        // docs/firestore-schema-migration.md).
        'fullName': fullName.trim(),
        'name': fullName.trim(),
        'email': email.trim(),
        'role': role,
        'approvalStatus': role == 'farmer' ? 'pending' : 'approved',
        // Buyers have no verification step, so they're verified on
        // creation; farmers become verified once an admin approves them
        // (see VerificationQueueView._approveFarmer).
        'isVerified': role != 'farmer',
        'createdAt': FieldValue.serverTimestamp(),
        'termsAccepted': true,
        'termsAcceptedAt': FieldValue.serverTimestamp(),
        if (role == 'farmer') 'supportedProductsAcknowledged': supportedProductsAcknowledged,
        if (role == 'farmer') 'supportedProductsAcknowledgedAt': FieldValue.serverTimestamp(),
      });
      return null;
    } on FirebaseAuthException catch (e) {
      return _messageFromCode(e.code);
    } catch (e) {
      return 'Something went wrong. Please try again.';
    }
  }

  Future<String?> saveVerificationDocument({
    required String uid,
    required String documentUrl,
    required String barangay,
    required String fullName,
  }) async {
    try {
      final db = FirebaseFirestore.instance;

      await db.collection('verificationDocs').doc(uid).set({
        'document': documentUrl,
        'submittedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'fullName': fullName.trim(),
        'userId': uid,
      }, SetOptions(merge: true));

      await db.collection('users').doc(uid).update({
        'barangay': barangay,
        'municipality': 'Laurel',
        'province': 'Batangas',
        'approvalStatus': 'pending',
        'hasVerificationDoc': true,
      });

      return null;
    } catch (e) {
      return 'Could not save the document. Please try again.';
    }
  }

  // Buyers have no verification step (see signUp's approvalStatus
  // comment) and aren't restricted to Laurel the way farmers are — just a
  // map pin (MyLocationField/PickLocationScreen) anywhere in the
  // Philippines, so unlike farmers there's no barangay/municipality/
  // province to store, only the raw coordinates.
  Future<String?> saveBuyerLocation({
    required String uid,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'latitude': latitude,
        'longitude': longitude,
      }, SetOptions(merge: true));
      return null;
    } catch (e) {
      return 'Could not save your location. Please try again.';
    }
  }

  Future<String?> createPendingVerificationApplication({
    required String uid,
    required String fullName,
    required String barangay,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('verificationDocs')
          .doc(uid)
          .set({
            'document': '',
            'submittedAt': FieldValue.serverTimestamp(),
            'status': 'pending',
            'fullName': fullName.trim(),
            'userId': uid,
          }, SetOptions(merge: true));

      await _users.doc(uid).set({
        'barangay': barangay,
        'municipality': 'Laurel',
        'province': 'Batangas',
        'approvalStatus': 'pending',
        'hasVerificationDoc': false,
      }, SetOptions(merge: true));
      return null;
    } catch (_) {
      return 'Hindi naisave ang application. Subukan ulit.';
    }
  }

  //At lumping gun
  // ----------------------------------------------------------
  // READ the document — used by the admin dashboard in Week 10
  // so an officer can look at it before approving (FR-028).
  // ----------------------------------------------------------
  Future<String?> getVerificationDocument(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('verificationDocs')
          .doc(uid)
          .get();

      if (!doc.exists) return null;
      return doc.data()?['document'] as String?;
    } catch (e) {
      return null;
    }
  }

  Future<void> _ensureGoogleSignInReady() async {
    if (_googleSignInReady) return;
    // No clientId/serverClientId here — on Android/iOS these come from
    // google-services.json / GoogleService-Info.plist automatically, as
    // long as Google is enabled as a Sign-In provider in the Firebase
    // Console (that step is what populates the web OAuth client those
    // files need).
    await _googleSignIn.initialize();
    _googleSignInReady = true;
  }

  // "Continue with Google". Returns GoogleSignInOutcome.needsProfile when
  // this Google account has no users/{uid} doc yet (first time signing in
  // with it) — the caller should collect a role (and, for farmers,
  // barangay + certificate) rather than route them into the app.
  Future<GoogleSignInResult> signInWithGoogle() async {
    try {
      await _ensureGoogleSignInReady();
      final account = await _googleSignIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        return const GoogleSignInResult.error('Could not sign in with Google. Please try again.');
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final userCred = await _auth.signInWithCredential(credential);
      final uid = userCred.user?.uid;
      if (uid == null) {
        return const GoogleSignInResult.error('Something went wrong. Please try again.');
      }

      final doc = await _users.doc(uid).get();
      if (doc.exists) {
        return GoogleSignInResult.signedIn(uid);
      }
      return GoogleSignInResult.needsProfile(
        uid: uid,
        email: userCred.user?.email ?? account.email,
        displayName: userCred.user?.displayName ?? account.displayName,
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return const GoogleSignInResult.cancelled();
      }
      return const GoogleSignInResult.error('Google sign-in failed. Please try again.');
    } on FirebaseAuthException catch (e) {
      return GoogleSignInResult.error(_messageFromCode(e.code));
    } catch (e) {
      return const GoogleSignInResult.error('Something went wrong. Please try again.');
    }
  }

  // Creates the users/{uid} doc for a Google account signing in for the
  // very first time — the same shape signUp() writes, minus the
  // password-account-only fields. Google already verifies the email, so
  // there's no separate email-verification step for this path.
  Future<String?> completeGoogleProfile({
    required String uid,
    required String fullName,
    required String email,
    required String role,
    bool supportedProductsAcknowledged = false,
  }) async {
    try {
      await _auth.currentUser?.updateDisplayName(fullName.trim());
      await _users.doc(uid).set({
        'fullName': fullName.trim(),
        'name': fullName.trim(),
        'email': email.trim(),
        'role': role,
        'approvalStatus': role == 'farmer' ? 'pending' : 'approved',
        'isVerified': role != 'farmer',
        'authProvider': 'google',
        'createdAt': FieldValue.serverTimestamp(),
        'termsAccepted': true,
        'termsAcceptedAt': FieldValue.serverTimestamp(),
        if (role == 'farmer') 'supportedProductsAcknowledged': supportedProductsAcknowledged,
        if (role == 'farmer') 'supportedProductsAcknowledgedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return null;
    } catch (e) {
      return 'Something went wrong. Please try again.';
    }
  }

  // Log in. If expectedRole is given, also verify the account's role
  // matches the login door used (e.g. a buyer account signing in through
  // the farmer-specific door). Pass null for a role-agnostic login — the
  // caller is then responsible for looking up the account's real role
  // afterward (see LoginScreen's generic login path).
  Future<String?> logIn({
    required String email,
    required String password,
    String? expectedRole,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (expectedRole != null) {
        final doc = await _users.doc(cred.user!.uid).get();
        final role = doc.data()?['role'];
        if (role != null && role != expectedRole) {
          await _auth.signOut();
          return 'ROLE_MISMATCH:$role';
        }
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return _messageFromCode(e.code);
    } catch (e) {
      return 'Something went wrong. Please try again.';
    }
  }

  // ============================================================
  // VERIFICATION METHODS — copy these INTO your auth_service.dart
  // ------------------------------------------------------------
  // This is not a standalone file. Paste these methods inside
  // your existing AuthService class, next to signUp() and logIn().
  //
  // Make sure these two imports are at the top of the file:
  //   import 'package:firebase_auth/firebase_auth.dart';
  //   import 'package:cloud_firestore/cloud_firestore.dart';
  // ============================================================

  // ----------------------------------------------------------
  // 1. SEND THE VERIFICATION EMAIL
  // ----------------------------------------------------------
  // Firebase sends a real email with a clickable link. There is
  // nothing for the user to type — they just tap the link.
  //
  // Returns null on success, or a message to show the user.
  // ----------------------------------------------------------
  Future<String?> sendVerificationEmail() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        return 'Walang naka-log in na account.';
      }
      if (user.emailVerified) {
        return null; // already done, nothing to send
      }

      await user.sendEmailVerification();
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'too-many-requests') {
        return 'Masyadong madalas. Maghintay ng ilang minuto.';
      }
      return 'Hindi naipadala ang email. Subukan ulit.';
    } catch (e) {
      return 'May problema sa koneksyon.';
    }
  }

  // ----------------------------------------------------------
  // 2. CHECK IF THEY CLICKED THE LINK YET
  // ----------------------------------------------------------
  // ⚠️ The reload() line is the important one. Firebase caches
  // the old "not verified" answer, so without reload() your app
  // would wait forever even after the user verified.
  // ----------------------------------------------------------
  Future<bool> isEmailVerified() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      await user.reload(); // fetch the latest status from Firebase
      final refreshed = FirebaseAuth.instance.currentUser;
      return refreshed?.emailVerified ?? false;
    } catch (e) {
      return false;
    }
  }

  // ----------------------------------------------------------
  // 3. HAS THE ADMIN APPROVED THIS FARMER? (FR-028)
  // ----------------------------------------------------------
  // Reads the approvalStatus field from the user's Firestore
  // document. Returns 'pending', 'approved', or 'rejected'.
  //
  // NOTE: change 'users' below if your collection has a
  // different name.
  // ----------------------------------------------------------
  Future<String> getFarmerApprovalStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 'pending';

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) return 'pending';

      final data = doc.data();
      return (data?['approvalStatus'] ?? 'pending').toString();
    } catch (e) {
      return 'pending';
    }
  }

  // ----------------------------------------------------------
  // 4. SIGN OUT — skip if you already have one.
  // ----------------------------------------------------------
  Future<void> signOut() async {
    // Must run before FirebaseAuth.signOut() — it needs to know which
    // account's fcmTokens to clean up this device's token from (see
    // PushNotificationService.unregisterToken's doc comment).
    await PushNotificationService().unregisterToken();
    await FirebaseAuth.instance.signOut();
    // Also drop the cached Google session, if any, so a later "Continue
    // with Google" doesn't silently re-use it. Harmless no-op if this
    // device never signed in with Google.
    if (_googleSignInReady) {
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
    }
  }

  // ----------------------------------------------------------
  // FORGOT PASSWORD — sends a reset link to the given email.
  // Works the same for farmer, buyer, and admin accounts since
  // they're all just Firebase Auth users underneath.
  // ----------------------------------------------------------
  Future<String?> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return _messageFromCode(e.code);
    } catch (e) {
      return 'Could not send the reset email. Please try again.';
    }
  }

  // ----------------------------------------------------------
  // CHANGE PASSWORD — for an already-logged-in user. Firebase
  // requires a recent sign-in before this kind of sensitive
  // change, so we re-authenticate with their current password
  // first (this also doubles as verifying they know it).
  // ----------------------------------------------------------
  Future<String?> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = _auth.currentUser;
      final email = user?.email;
      if (user == null || email == null) {
        return 'You are not logged in.';
      }

      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
      return null;
    } on FirebaseAuthException catch (e) {
      return _messageFromCode(e.code);
    } catch (e) {
      return 'Could not update your password. Please try again.';
    }
  }

  // ============================================================
  // ONE MORE CHANGE — inside your existing signUp() method
  // ------------------------------------------------------------
  // Where you save the new user to Firestore, add this field so
  // the admin has something to approve later:
  //
  //     'approvalStatus': role == 'farmer' ? 'pending' : 'approved',
  //
  // Buyers are auto-approved because your paper only requires
  // admin verification for SELLERS (FR-028).
  //
  // And right after creating the account, send the email:
  //
  //     await FirebaseAuth.instance.currentUser
  //         ?.sendEmailVerification();
  // ============================================================

  Future<void> logOut() async {
    await signOut();
  }

  String _messageFromCode(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'That email is already registered. Try logging in.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'requires-recent-login':
        return 'Please log out and back in, then try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a bit and try again.';
      case 'network-request-failed':
        return 'No internet connection. Please check your connection and try again.';
      default:
        return 'Login failed. Please try again.';
    }
  }

  // ── Admin: fetch farmers awaiting approval ──
  // Returns a real-time stream so the dashboard updates automatically
  // whenever a new farmer registers or an admin approves/rejects someone.
  //
  // Deliberately filters only on role, not on approvalStatus — a Firestore
  // equality filter (`isEqualTo: 'pending'`) never matches a document where
  // the field is absent entirely, so a legacy farmer account that predates
  // the approvalStatus field would silently never appear in this query,
  // with no way for an admin to ever approve them short of the Firebase
  // Console. The caller filters to "pending or missing" client-side
  // instead (see verification_queue_view.dart) — same "missing defaults to
  // pending" convention already used by AuthRoutingService/
  // PendingApprovalScreen/getFarmerApprovalStatus.
  Stream<QuerySnapshot<Map<String, dynamic>>> getPendingFarmers() {
    return FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'farmer')
        .snapshots();
  }
}
