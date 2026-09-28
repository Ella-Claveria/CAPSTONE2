import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Lets a signed-in user (buyer or farmer) file a support request and see
/// the ones they've already sent. Requests are read/managed by admins from
/// Firestore directly for now — no admin review screen exists yet.
class SupportRequestService {
  final _requests = FirebaseFirestore.instance.collection('supportRequests');

  Future<String?> submit({required String subject, required String message}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Please log in again and try once more.';
    if (subject.trim().isEmpty || message.trim().isEmpty) {
      return 'Please fill in both the subject and your message.';
    }

    try {
      await _requests.add({
        'userId': user.uid,
        'userName': user.displayName ?? '',
        'userEmail': user.email ?? '',
        'subject': subject.trim(),
        'message': message.trim(),
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (_) {
      return 'Could not send your request. Please try again.';
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> myRequestsStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return _requests.where('userId', isEqualTo: uid).snapshots();
  }
}
