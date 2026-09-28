import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ApplicationUnderReviewScreen extends StatelessWidget {
  // In a real app, these boolean values would stream from Firestore 
  // based on the current user's document status.
  final bool isEmailVerified = false;
  final bool isDocumentScreened = true; // Assume document was successfully uploaded/scanned
  final bool isComplianceApproved = false;

  const ApplicationUnderReviewScreen({super.key});

  void _returnToLogin(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your Application is\nUnder Review',
                style: TextStyle(
                  fontSize: 32,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E4022),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'To maintain platform integrity, all registrations are subject to manual review. Approval normally takes 24-48 business hours.',
                style: TextStyle(fontSize: 16, height: 1.5, color: Colors.grey[700]),
              ),
              const SizedBox(height: 32),
              
              // Checklist
              _buildStatusRow(
                title: 'Email Address Verification',
                subtitle: 'Check your inbox for the activation link.',
                isComplete: isEmailVerified,
              ),
              _buildStatusRow(
                title: 'Document Screening',
                subtitle: 'Reviewing your Agricultural Certification.',
                isComplete: isDocumentScreened,
              ),
              _buildStatusRow(
                title: 'Compliance Approval',
                subtitle: 'Final clearance by an Agricultural Officer.',
                isComplete: isComplianceApproved,
              ),
              
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () => _returnToLogin(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D4A22),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Return to Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusRow({required String title, required String subtitle, required bool isComplete}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isComplete ? Colors.green[800] : Colors.grey[300],
              shape: BoxShape.circle,
            ),
            child: Icon(
              isComplete ? Icons.check : Icons.hourglass_empty,
              color: isComplete ? Colors.white : Colors.grey[600],
              size: 16,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isComplete ? Colors.black87 : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}