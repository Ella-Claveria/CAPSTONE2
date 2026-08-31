import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _users = FirebaseFirestore.instance.collection('users');

  // Create an account with a role ('farmer' or 'buyer').
  Future<String?> signUp({
    required String fullName,
    required String email,
    required String password,
    required String role,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      await cred.user?.updateDisplayName(fullName.trim());
      await _users.doc(cred.user!.uid).set({
        'fullName': fullName.trim(),
        'email': email.trim(),
        'role': role,
        'approvalStatus': role == 'farmer' ? 'pending' : 'approved',
        'createdAt': FieldValue.serverTimestamp(),
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
      return 'Hindi naisave ang dokumento. Subukan ulit.';
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

  // Log in and verify the account's role matches the login door used.
  Future<String?> logIn({
    required String email,
    required String password,
    required String expectedRole,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final doc = await _users.doc(cred.user!.uid).get();
      final role = doc.data()?['role'];
      if (role != null && role != expectedRole) {
        await _auth.signOut();
        return 'ROLE_MISMATCH:$role';
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
    await FirebaseAuth.instance.signOut();
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
    await _auth.signOut();
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
      default:
        return 'Login failed. Please try again.';
    }
  }

  // ── Admin: fetch farmers awaiting approval ──
  // Returns a real-time stream so the dashboard updates automatically
  // whenever a new farmer registers or an admin approves/rejects someone.
  Stream<QuerySnapshot> getPendingFarmers() {
    return FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'farmer')
        .where('approvalStatus', isEqualTo: 'pending')
        .snapshots();
  }

  // ── Admin: approve a farmer application ──
  Future<void> approveFarmer(String uid) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'approvalStatus': 'approved',
    });
  }

  // ── Admin: reject a farmer application ──
  Future<void> rejectFarmer(String uid) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'approvalStatus': 'rejected',
    });
  }
}
