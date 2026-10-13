import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'presence_service.dart';
import 'push_notification_service.dart';

/// Everything collected on the registration form that still needs to be
/// written to Firestore once email verification actually succeeds — see
/// AuthService.completeRegistration/EmailVerificationScreen. Persisted
/// locally (AuthService.savePendingProfile) the moment the Firebase Auth
/// account is created, so it survives the app being closed/killed while
/// the user is off checking their email, not just an in-memory navigation
/// argument.
class PendingRegistrationProfile {
  // Stored here (not just read from EmailVerificationScreen.role) because
  // that widget field falls back to a guessed 'buyer' default when this
  // screen is reached by resuming an unverified session from a fresh app
  // launch (see AuthRoutingService.decideFromData) — the role actually
  // registered must always come from this authoritative, originally-typed
  // value instead, or a resumed farmer could get mis-registered as an
  // auto-approved buyer.
  final String role;
  final String fullName;
  final String? mobileNumber;
  final bool supportedProductsAcknowledged;
  // Farmer-only.
  final String? barangay;
  final String? certificateUrl;
  // As typed on the form, for the admin to check (see rsba_number.dart).
  final String? rsbaNumber;

  const PendingRegistrationProfile({
    required this.role,
    required this.fullName,
    this.mobileNumber,
    this.supportedProductsAcknowledged = false,
    this.barangay,
    this.certificateUrl,
    this.rsbaNumber,
  });

  Map<String, dynamic> toJson() => {
    'role': role,
    'fullName': fullName,
    'mobileNumber': mobileNumber,
    'supportedProductsAcknowledged': supportedProductsAcknowledged,
    'barangay': barangay,
    'certificateUrl': certificateUrl,
    'rsbaNumber': rsbaNumber,
  };

  static PendingRegistrationProfile fromJson(Map<String, dynamic> json) =>
      PendingRegistrationProfile(
        role: json['role'] as String? ?? 'buyer',
        fullName: json['fullName'] as String? ?? '',
        mobileNumber: json['mobileNumber'] as String?,
        supportedProductsAcknowledged:
            json['supportedProductsAcknowledged'] as bool? ?? false,
        barangay: json['barangay'] as String?,
        certificateUrl: json['certificateUrl'] as String?,
        rsbaNumber: json['rsbaNumber'] as String?,
      );
}

/// Result of [AuthService.requestEmailOtp].
class EmailOtpRequestResult {
  /// A message to show the user, or null if the request went through.
  final String? error;

  /// Which step failed, for logs and tests — never shown to the user:
  /// 'not-found' (function not deployed / wrong region), 'unauthenticated',
  /// 'cooldown', 'rate-limit', 'firestore-write', 'auth-lookup',
  /// 'smtp-auth', 'smtp-connection', 'smtp-send'.
  final String? errorCode;

  /// A new code was emailed (false when the one already sent still works).
  final bool sent;

  /// The account's email is already verified — there is nothing to enter.
  final bool alreadyVerified;

  /// How long "Resend Code" should stay locked.
  final int resendAfterSeconds;

  const EmailOtpRequestResult({
    this.error,
    this.errorCode,
    this.sent = false,
    this.alreadyVerified = false,
    this.resendAfterSeconds = 0,
  });
}

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
  final String? photoUrl;
  final String? message;

  const GoogleSignInResult._(
    this.outcome, {
    this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.message,
  });

  const GoogleSignInResult.signedIn(String uid)
    : this._(GoogleSignInOutcome.signedIn, uid: uid);

  const GoogleSignInResult.needsProfile({
    required String uid,
    required String? email,
    required String? displayName,
    String? photoUrl,
  }) : this._(
         GoogleSignInOutcome.needsProfile,
         uid: uid,
         email: email,
         displayName: displayName,
         photoUrl: photoUrl,
       );

  const GoogleSignInResult.cancelled() : this._(GoogleSignInOutcome.cancelled);

  const GoogleSignInResult.error(String message)
    : this._(GoogleSignInOutcome.error, message: message);
}

class AuthService {
  static const String adminEmailWithoutVerification = 'admin@agritrade.com';
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // Region of the account-email Cloud Functions (functions/account_emails.js).
  static final FirebaseFunctions _accountEmails = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );
  final _users = FirebaseFirestore.instance.collection('users');
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleSignInReady = false;

  Future<String?> refreshVerifiedEmailToken() async {
    final user = _auth.currentUser;
    if (user == null) return 'Please log in again.';
    try {
      await user.reload();
      final refreshed = _auth.currentUser;
      if (refreshed == null) return 'Please log in again.';
      final isAdminAccount =
          refreshed.email?.trim().toLowerCase() ==
          adminEmailWithoutVerification;
      if (!refreshed.emailVerified && !isAdminAccount) {
        return 'Verify your email before continuing.';
      }
      // Firestore Rules validate the refreshed Firebase email_verified
      // token claim directly. Login must not depend on a separately
      // deployed callable just to refresh verification state.
      await refreshed.getIdToken(true);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'user-disabled') {
        return 'Please log in again.';
      }
      return e.code == 'network-request-failed'
          ? 'Check your internet connection and try again.'
          : 'Could not verify your account right now. Please try again.';
    } catch (_) {
      return 'Could not verify your account right now. Please try again.';
    }
  }

  // The signed-in user's UID, or null if nobody's logged in.
  String? get currentUid => _auth.currentUser?.uid;
  String? get currentEmail => _auth.currentUser?.email;

  // Creates ONLY the Firebase Auth account — no users/{uid} Firestore
  // document yet. That document (role, name, barangay, certificate, etc.)
  // is written later, in one shot, by completeRegistration() once email
  // verification actually succeeds — see EmailVerificationScreen. This is
  // deliberate: an account that never gets verified should never leave a
  // half-registered profile sitting in Firestore, and Firebase itself has
  // no concept of "verify an email" for an account that doesn't exist yet,
  // so creating the Auth account first is unavoidable either way.
  Future<String?> signUp({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return null;
    } on FirebaseAuthException catch (e) {
      return _messageFromCode(e.code);
    } catch (e) {
      return 'Something went wrong. Please try again.';
    }
  }

  // The one, consolidated write that used to happen immediately inside
  // signUp() (plus, for farmers, a second write from saveVerificationDocument)
  // — now deferred until EmailVerificationScreen confirms the email was
  // actually verified. Safe to call more than once with the same data
  // (merge: true), so a retry after a transient failure never duplicates
  // anything.
  Future<String?> completeRegistration({
    required String uid,
    required String fullName,
    required String email,
    required String role,
    // Already in "+63XXXXXXXXXX" form (see RegisterScreen._register) — this
    // is contact info only, never used for phone-number auth/OTP.
    String? mobileNumber,
    // Farmer-only.
    bool supportedProductsAcknowledged = false,
    String? barangay,
    String? certificateUrl,
    // Stored for the admin reviewing the farmer; it approves nothing on
    // its own (see rsba_number.dart).
    String? rsbaNumber,
    // True when this follows a correct email code. firestore.rules only
    // accepts the field if the server recorded that check as passed.
    bool emailOtpVerified = false,
  }) async {
    final isFarmer = role == 'farmer';
    final rsba = isFarmer ? (rsbaNumber ?? '').trim() : '';
    try {
      await _auth.currentUser?.updateDisplayName(fullName.trim());
      await _users.doc(uid).set({
        // 'fullName' is kept for backward compatibility with older reads;
        // 'name' is the standardized display-name field going forward
        // (matches what EditProfileScreen writes on later edits — see
        // docs/firestore-schema-migration.md).
        'fullName': fullName.trim(),
        'name': fullName.trim(),
        'email': email.trim(),
        if (mobileNumber != null && mobileNumber.isNotEmpty)
          'mobileNumber': mobileNumber,
        'role': role,
        'approvalStatus': isFarmer ? 'pending' : 'approved',
        // Buyers have no verification step, so they're verified on
        // creation; farmers become verified once an admin approves them
        // (see VerificationQueueView._approveFarmer).
        'isVerified': !isFarmer,
        if (emailOtpVerified) 'emailOtpVerified': true,
        'createdAt': FieldValue.serverTimestamp(),
        'termsAccepted': true,
        'termsAcceptedAt': FieldValue.serverTimestamp(),
        if (isFarmer)
          'supportedProductsAcknowledged': supportedProductsAcknowledged,
        if (isFarmer)
          'supportedProductsAcknowledgedAt': FieldValue.serverTimestamp(),
        if (isFarmer && barangay != null) 'barangay': barangay,
        if (isFarmer) 'municipality': 'Laurel',
        if (isFarmer) 'province': 'Batangas',
        if (isFarmer && certificateUrl != null) 'hasVerificationDoc': true,
        if (rsba.isNotEmpty) 'rsbaNumber': rsba,
      }, SetOptions(merge: true));

      // What the farmer submitted for the admin to review: a certificate
      // image (older registrations, Google sign-up) or an RSBA number.
      if (isFarmer && (certificateUrl != null || rsba.isNotEmpty)) {
        await FirebaseFirestore.instance
            .collection('verificationDocs')
            .doc(uid)
            .set({
              'document': ?certificateUrl,
              if (rsba.isNotEmpty) 'rsbaNumber': rsba,
              'submittedAt': FieldValue.serverTimestamp(),
              'status': 'pending',
              'fullName': fullName.trim(),
              'userId': uid,
            }, SetOptions(merge: true));
      }
      return null;
    } catch (e) {
      return 'Could not finish setting up your account. Please try again.';
    }
  }

  // ---- Local, on-device storage for PendingRegistrationProfile ----
  // (see that class's doc comment for why this exists). Keyed by uid so a
  // device that has registered more than one account never mixes them up.
  static const _pendingProfileKeyPrefix = 'pending_registration_';

  Future<void> savePendingProfile(
    String uid,
    PendingRegistrationProfile profile,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_pendingProfileKeyPrefix$uid',
        jsonEncode(profile.toJson()),
      );
    } catch (_) {
      // Non-fatal — completeRegistration falls back to best-effort data if
      // this was never saved or got lost (see EmailVerificationScreen).
    }
  }

  Future<PendingRegistrationProfile?> loadPendingProfile(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_pendingProfileKeyPrefix$uid');
      if (raw == null) return null;
      return PendingRegistrationProfile.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clearPendingProfile(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_pendingProfileKeyPrefix$uid');
    } catch (_) {}
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
  // comment) and aren't restricted to Laurel the way farmers are — the
  // buyer location popup (see buyer_location_picker.dart), shown when
  // placing an order, either reverse-geocodes a GPS fix or reads a
  // Region/Province/City/Barangay picked from a PSGC-backed drill-down.
  //
  /// Exact coordinates live under users/{uid}/private/geo, not on the main
  /// user doc — that doc is readable by any signed-in user (needed for
  /// public profile fields like name/barangay), so an exact pin must never
  /// be a field on it. Only the owner and an admin can read this
  /// subcollection (see firestore.rules); every other screen that needs a
  /// buyer's or farmer's approximate location uses barangay/municipality
  /// text or a server-aggregated point instead. The readable region/
  /// province/city/barangay, by contrast, are stored on the main doc —
  /// same as a farmer's barangay already is — since the admin Demand
  /// Heatmap and this buyer's own profile ("Saved Location") both need to
  /// read them, and they're already not sensitive precise-location data.
  ///
  /// [latitude]/[longitude] are omitted when the buyer picked their
  /// location manually and the forward-geocode fallback failed — that's
  /// non-fatal, since the readable address is what actually matters here;
  /// a coordinate is only a bonus for the Demand Heatmap/approximate
  /// distance. Pass only the fields that changed; omitted ones are left
  /// untouched on the existing doc (e.g. "Edit Location" picking a new
  /// barangay without re-detecting GPS doesn't erase a previously saved
  /// pin).
  Future<String?> saveBuyerLocation({
    required String uid,
    double? latitude,
    double? longitude,
    String? region,
    String? province,
    String? city,
    String? barangay,
  }) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

      if (latitude != null && longitude != null) {
        batch.set(userRef.collection('private').doc('geo'), {
          'latitude': latitude,
          'longitude': longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (region != null ||
          province != null ||
          city != null ||
          barangay != null) {
        batch.set(userRef, {
          'region': ?region,
          'province': ?province,
          // Kept as "municipality" (not "city") so this lines up with
          // the field name DashboardAnalyticsService's Demand Heatmap
          // already reads for every account, farmer and buyer alike.
          'municipality': ?city,
          'barangay': ?barangay,
        }, SetOptions(merge: true));
      }

      await batch.commit();
      return null;
    } catch (e) {
      return 'Could not save your location. Please try again.';
    }
  }

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
      GoogleSignInAccount? account;
      final UserCredential userCred;
      if (kIsWeb) {
        // The web build (Admin Portal) can't use google_sign_in's
        // authenticate() — it isn't supported in the browser — so Firebase
        // Auth runs the Google popup itself. The role check still happens
        // in the caller, exactly as for the mobile path.
        userCred = await _auth.signInWithPopup(
          GoogleAuthProvider()
            ..setCustomParameters({'prompt': 'select_account'}),
        );
      } else {
        await _ensureGoogleSignInReady();
        account = await _googleSignIn.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) {
          return const GoogleSignInResult.error(
            'Could not log in with Google. Please try again.',
          );
        }

        final credential = GoogleAuthProvider.credential(idToken: idToken);
        userCred = await _auth.signInWithCredential(credential);
      }
      final uid = userCred.user?.uid;
      if (uid == null) {
        return const GoogleSignInResult.error(
          'Something went wrong. Please try again.',
        );
      }

      final doc = await _users.doc(uid).get();
      if (doc.exists) {
        final profile = doc.data() ?? const <String, dynamic>{};
        final savedName = (profile['name'] ?? profile['fullName'])
            ?.toString()
            .trim();
        final savedPhoto = profile['photoUrl']?.toString().trim();
        if (savedName != null && savedName.isNotEmpty) {
          await userCred.user?.updateDisplayName(savedName);
        }
        if (savedPhoto != null && savedPhoto.isNotEmpty) {
          await userCred.user?.updatePhotoURL(savedPhoto);
        }
        final verificationError = await refreshVerifiedEmailToken();
        if (verificationError != null) {
          return GoogleSignInResult.error(verificationError);
        }
        return GoogleSignInResult.signedIn(uid);
      }
      return GoogleSignInResult.needsProfile(
        uid: uid,
        email: userCred.user?.email ?? account?.email,
        displayName: userCred.user?.displayName ?? account?.displayName,
        photoUrl: userCred.user?.photoURL ?? account?.photoUrl,
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return const GoogleSignInResult.cancelled();
      }
      return const GoogleSignInResult.error(
        'Google login failed. Please try again.',
      );
    } on FirebaseAuthException catch (e) {
      // Web popup closed or superseded by another one — not an error.
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request' ||
          e.code == 'web-context-cancelled') {
        return const GoogleSignInResult.cancelled();
      }
      if (e.code == 'popup-blocked') {
        return const GoogleSignInResult.error(
          'Your browser blocked the Google login window. Allow pop-ups for this site and try again.',
        );
      }
      return GoogleSignInResult.error(_messageFromCode(e.code));
    } catch (e) {
      return const GoogleSignInResult.error(
        'Something went wrong. Please try again.',
      );
    }
  }

  // Whether the signed-in account has a password at all — a Google-only
  // account has none to change (see the change-password dialog).
  bool get hasPasswordProvider =>
      _auth.currentUser?.providerData.any(
        (p) => p.providerId == EmailAuthProvider.PROVIDER_ID,
      ) ??
      false;

  // Creates the users/{uid} doc for a Google account signing in for the
  // very first time — the same shape signUp() writes, minus the
  // password-account-only fields. Google already verifies the email, so
  // there's no separate email-verification step for this path.
  Future<String?> completeGoogleProfile({
    required String uid,
    required String fullName,
    required String email,
    required String role,
    String? photoUrl,
    // Already in "+63XXXXXXXXXX" form — see signUp's mobileNumber doc.
    String? mobileNumber,
    bool supportedProductsAcknowledged = false,
  }) async {
    try {
      await _auth.currentUser?.updateDisplayName(fullName.trim());
      if (photoUrl != null && photoUrl.isNotEmpty) {
        await _auth.currentUser?.updatePhotoURL(photoUrl);
      }
      await _users.doc(uid).set({
        'fullName': fullName.trim(),
        'name': fullName.trim(),
        'email': email.trim(),
        if (mobileNumber != null && mobileNumber.isNotEmpty)
          'mobileNumber': mobileNumber,
        'role': role,
        'approvalStatus': role == 'farmer' ? 'pending' : 'approved',
        'isVerified': role != 'farmer',
        'authProvider': 'google',
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'termsAccepted': true,
        'termsAcceptedAt': FieldValue.serverTimestamp(),
        if (role == 'farmer')
          'supportedProductsAcknowledged': supportedProductsAcknowledged,
        if (role == 'farmer')
          'supportedProductsAcknowledgedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final verificationError = await refreshVerifiedEmailToken();
      if (verificationError != null) return verificationError;
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
    // Paused after too many wrong passwords? The server decides — see the
    // failed-login cooldown below.
    final gate = await _loginThrottle('checkLoginAllowed', {
      'email': email.trim(),
    });
    if (gate?['locked'] == true) return _lockedSentinel(gate!);

    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      // The password was right, so the run of failures is over. Skipped
      // when the server already said there were none to clear.
      if (gate == null || gate['attemptsRemaining'] != loginMaxFailedAttempts) {
        await _loginThrottle('clearLoginFailures');
      }
      if (expectedRole != null) {
        final doc = await _users.doc(cred.user!.uid).get();
        final role = doc.data()?['role'];
        if (role != null && role != expectedRole) {
          await _auth.signOut();
          return 'ROLE_MISMATCH:$role';
        }
      }
      final isAdminAccount =
          cred.user?.email?.trim().toLowerCase() ==
          adminEmailWithoutVerification;
      if (cred.user?.emailVerified == true || isAdminAccount) {
        final verificationError = await refreshVerifiedEmailToken();
        if (verificationError != null) return verificationError;
      }
      return null;
    } on FirebaseAuthException catch (e) {
      // Firebase Authentication's own abuse protection. It does not say
      // how long it lasts, so the caller shows the dialog with no timer.
      if (e.code == 'too-many-requests') return loginRateLimitedSentinel;

      // An unknown email, a wrong password and a Google-only account all
      // get the same answer and are counted the same way, so nothing here
      // tells the caller whether the email is registered.
      const wrongCredentials = {
        'user-not-found',
        'wrong-password',
        'invalid-credential',
      };
      if (wrongCredentials.contains(e.code)) {
        final outcome = await _loginThrottle('reportLoginFailure', {
          'email': email.trim(),
        });
        if (outcome?['locked'] == true) return _lockedSentinel(outcome!);
        final remaining = (outcome?['attemptsRemaining'] as num?)?.toInt();
        // After the 3rd and 4th wrong password: warn how many tries are
        // left. The first two, and any failure the server could not count,
        // get the plain message below with no number.
        if (remaining != null && remaining > 0 && remaining <= 2) {
          return '$wrongCredentialsMessage You have $remaining '
              '${remaining == 1 ? 'attempt' : 'attempts'} left.';
        }
      }
      return _messageFromCode(e.code);
    } catch (e) {
      return 'Something went wrong. Please try again.';
    }
  }

  // ----------------------------------------------------------
  // FAILED-LOGIN COOLDOWN — 5 wrong passwords in a row pause password
  // login for that email for 5 minutes.
  //
  // The count and the pause are kept by Cloud Functions
  // (functions/login_throttle.js), keyed by the email, so restarting the
  // app, clearing its storage or switching devices does not reset them.
  // Nothing is stored on this device, the Firebase account itself is
  // never disabled, and Forgot Password keeps working during the pause.
  // ----------------------------------------------------------

  /// The wrong-email-or-password result from logIn. On its own for the
  /// first two failures; followed by the attempts remaining once only two
  /// or one are left, which the login form shows under the Password field
  /// instead of as a pop-up.
  static const String wrongCredentialsMessage = 'Incorrect email or password.';

  /// Wrong passwords in a row before the pause (mirrors the server).
  static const int loginMaxFailedAttempts = 5;

  /// logIn result while the pause is running, followed by the seconds
  /// left: `LOGIN_LOCKED:240`.
  static const String loginLockedPrefix = 'LOGIN_LOCKED:';

  /// logIn result when Firebase Authentication itself is rate-limiting.
  static const String loginRateLimitedSentinel = 'LOGIN_RATE_LIMITED';

  static String _lockedSentinel(Map<dynamic, dynamic> data) {
    final seconds = (data['retryAfterSeconds'] as num?)?.toInt() ?? 300;
    return '$loginLockedPrefix$seconds';
  }

  // Calls one of the cooldown functions. Null means the server could not
  // be asked (offline, slow, not deployed): login then simply goes ahead
  // with Firebase Authentication's own protection, rather than every
  // login failing because this extra check is unavailable.
  Future<Map<dynamic, dynamic>?> _loginThrottle(
    String function, [
    Map<String, dynamic>? data,
  ]) async {
    try {
      final response = await _accountEmails
          .httpsCallable(
            function,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 6)),
          )
          .call<dynamic>(data);
      return response.data is Map ? response.data as Map : null;
    } catch (e) {
      debugPrint('[Auth] $function unavailable: $e');
      return null;
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
  // 1. SEND THE VERIFICATION CODE
  // ----------------------------------------------------------
  // The requestEmailOtp Cloud Function generates a 6-digit code and
  // emails it (functions/email_otp.js) — the code never exists in the
  // app until the user types it. This is the only verification email a
  // sign-up gets; Firebase's own link email is not sent.
  //
  // resend: false is the Verify Email screen opening — the server only
  // sends then if there is no code the user could still use, so a
  // rebuild or reopening the app never sends a second email.
  // resend: true is the user tapping "Resend Code".
  // ----------------------------------------------------------
  Future<EmailOtpRequestResult> requestEmailOtp({required bool resend}) async {
    if (_auth.currentUser == null) {
      return const EmailOtpRequestResult(error: 'Please log in again.');
    }
    try {
      final response = await _accountEmails
          .httpsCallable('requestEmailOtp')
          .call<dynamic>({'auto': !resend});
      final data = response.data is Map ? response.data as Map : const {};
      return EmailOtpRequestResult(
        sent: data['sent'] == true,
        alreadyVerified: data['alreadyVerified'] == true,
        resendAfterSeconds: (data['resendAfterSeconds'] as num?)?.toInt() ?? 0,
      );
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      final retryAfter = details is Map
          ? (details['retryAfterSeconds'] as num?)?.toInt() ?? 0
          : 0;
      // Which step failed on the server — see `fail()` in
      // functions/email_otp.js for the full list.
      final reason = details is Map ? details['reason']?.toString() : null;
      debugPrint(
        'requestEmailOtp failed: code=${e.code} reason=$reason '
        'message=${e.message}',
      );
      return EmailOtpRequestResult(
        error: switch (e.code) {
          // The function's own wording: cooldown / hourly limit.
          'resource-exhausted' =>
            e.message ?? 'Please wait before requesting another code.',
          'unauthenticated' =>
            'Your session has expired. Please log in again.',
          // No function of that name in that region.
          'not-found' =>
            'Email verification is not available yet. Please try again later.',
          'deadline-exceeded' =>
            'Check your internet connection and try again.',
          // Auth lookup, Firestore write or SMTP — the function says which.
          'internal' || 'unavailable' when reason != null =>
            e.message ??
                'Could not send the verification code. Please try again.',
          // 'unavailable' with no reason never reached the function.
          'unavailable' => 'Check your internet connection and try again.',
          _ => 'Could not send the verification code. Please try again.',
        },
        errorCode: reason ?? e.code,
        resendAfterSeconds: retryAfter,
      );
    } catch (e) {
      debugPrint('requestEmailOtp failed before reaching the server: $e');
      return const EmailOtpRequestResult(
        error: 'Could not send the verification code. Please try again.',
        errorCode: 'client-error',
      );
    }
  }

  // ----------------------------------------------------------
  // 2. CHECK THE CODE THE USER TYPED
  // ----------------------------------------------------------
  // Checked by the verifyEmailOtp Cloud Function, which also marks the
  // account's email as verified. Returns null on success, or a message
  // to show the user.
  // ----------------------------------------------------------
  Future<String?> verifyEmailOtp(String code) async {
    if (_auth.currentUser == null) return 'Please log in again.';
    try {
      await _accountEmails.httpsCallable('verifyEmailOtp').call<dynamic>({
        'code': code,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return switch (e.code) {
        // The function's own wording: incorrect / expired / too many attempts.
        'invalid-argument' ||
        'failed-precondition' ||
        'resource-exhausted' => e.message ?? 'Incorrect verification code.',
        'unauthenticated' => 'Please log in again.',
        _ => 'Could not verify the code. Please try again.',
      };
    } catch (_) {
      return 'Could not verify the code. Please try again.';
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
  //
  // [reason] is only for the debug log below — every caller that signs a
  // user out without them asking should say why, so an unexpected logout
  // can be traced to its trigger from the console.
  //
  // [keepPushToken] leaves this phone on the account's push list. Only for
  // a farmer who goes back to login while their application is still
  // under review: the decision is the one thing they are waiting for, and
  // it must be able to reach this phone. The token still belongs to one
  // account at a time (enforceExclusiveFcmToken in functions/index.js), so
  // it leaves this account the moment anyone else signs in here.
  Future<void> signOut({
    String reason = 'not specified',
    bool keepPushToken = false,
  }) async {
    final leaving = _auth.currentUser;
    debugPrint(
      '[Auth] signOut() called — reason: $reason '
      '(uid: ${leaving?.uid}, email: ${leaving?.email})',
    );
    // Must run before FirebaseAuth.signOut() — it needs to know which
    // account's fcmTokens to clean up this device's token from (see
    // PushNotificationService.unregisterToken's doc comment).
    if (keepPushToken) {
      debugPrint('[FCM] token KEPT on the account (application under review)');
    } else {
      await PushNotificationService().unregisterToken();
    }
    // Same reason: the "active now" dot must go off while this device can
    // still write the account's presence doc.
    await PresenceService.instance.goOffline();
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
  // they're all just Firebase Auth users underneath. Only an email
  // that's actually registered gets a link, but the caller is told the
  // same thing either way.
  // ----------------------------------------------------------
  Future<String?> sendPasswordResetEmail(String email) async {
    try {
      // Sent by the sendPasswordResetEmail Cloud Function (AgriTrade+
      // template, Gmail SMTP). Firebase Auth still makes and checks the
      // reset link itself.
      try {
        await _accountEmails.httpsCallable('sendPasswordResetEmail').call({
          'email': email.trim(),
        });
        return null;
      } on FirebaseFunctionsException catch (e) {
        if (e.code == 'resource-exhausted') {
          return 'A reset email was just sent. Please wait a minute before trying again.';
        }
        if (e.code == 'invalid-argument') {
          return 'Please enter a valid email address.';
        }
        // The function could not send it — fall back to Firebase's own
        // email below so the password can still be reset.
      }
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      // Reported as sent, exactly like a registered address, so this
      // screen cannot be used to find out which emails have accounts.
      if (e.code == 'user-not-found') return null;
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
      if (e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'user-mismatch') {
        return 'Current password is incorrect.';
      }
      return _messageFromCode(e.code);
    } catch (e) {
      return 'Could not update your password. Please try again.';
    }
  }

  // ----------------------------------------------------------
  // CHANGE EMAIL — for an already-logged-in password account.
  // Re-authenticates with the current password, then has Firebase
  // email a confirmation link to the NEW address; the sign-in email
  // only actually changes once that link is opened (so a typo can't
  // lock the account out, and the new address ends up verified).
  // Firebase signs the account out everywhere at that point — the
  // users/{uid} copy of the email is brought in line on the next
  // sign-in, see syncProfileEmail.
  // ----------------------------------------------------------
  Future<String?> requestEmailChange({
    required String currentPassword,
    required String newEmail,
  }) async {
    try {
      final user = _auth.currentUser;
      final email = user?.email;
      if (user == null || email == null) {
        return 'You are not logged in.';
      }
      final target = newEmail.trim();
      if (target.toLowerCase() == email.trim().toLowerCase()) {
        return 'That is already your current email.';
      }

      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: currentPassword),
      );
      await user.verifyBeforeUpdateEmail(target);
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
        case 'user-mismatch':
          return 'Current password is incorrect.';
        case 'email-already-in-use':
          return 'That email is already used by another account.';
        case 'invalid-email':
        case 'invalid-new-email':
          return 'Please enter a valid email address.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait a bit and try again.';
        case 'network-request-failed':
          return 'No internet connection. Please check your connection and try again.';
        default:
          return 'Could not start the email change. Please try again.';
      }
    } catch (e) {
      return 'Could not start the email change. Please try again.';
    }
  }

  // Copies the Firebase Auth email onto users/{uid}.email when the two
  // have drifted apart — i.e. the first sign-in after a confirmed
  // requestEmailChange. Best-effort: a failure here must never block a
  // login, and the next sign-in simply tries again.
  Future<void> syncProfileEmail() async {
    try {
      final user = _auth.currentUser;
      final email = user?.email?.trim();
      if (user == null || email == null || email.isEmpty) return;
      final ref = _users.doc(user.uid);
      final stored = (await ref.get()).data()?['email']?.toString().trim();
      // No email on the doc at all means it isn't stored there.
      if (stored == null || stored.toLowerCase() == email.toLowerCase()) {
        return;
      }
      await ref.update({'email': email});
    } catch (_) {}
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
    await signOut(reason: 'user tapped Log Out');
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
        return wrongCredentialsMessage;
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
