import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agritrade_text.dart';

/// Full-screen "forgot password" flow (farmer/buyer login door) — asks for
/// the account's email, sends a Firebase reset link to it so the user can
/// verify it's them and pick a new password, then confirms it was sent.
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _emailController = TextEditingController(text: widget.initialEmail);
  bool _sending = false;
  bool _sent = false;

  static const Color _dark = AppTheme.dark;
  static final _fieldRadius = BorderRadius.circular(30);

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address.')),
      );
      return;
    }
    setState(() => _sending = true);
    final error = await AuthService().sendPasswordResetEmail(email);
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _sent = true);
  }

  InputDecoration _decoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF2F2F2),
      prefixIcon: Icon(icon, color: Colors.grey),
      border: OutlineInputBorder(borderRadius: _fieldRadius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: _fieldRadius, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: _fieldRadius, borderSide: const BorderSide(color: _dark, width: 1.4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Image.asset(
                          'assets/logo.png',
                          width: 70,
                          height: 70,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 70,
                            height: 70,
                            decoration: const BoxDecoration(color: Color(0xFF2E7D32), shape: BoxShape.circle),
                            child: const Icon(Icons.agriculture, size: 38, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Center(child: AgriTradeText(fontSize: 26)),
                      const SizedBox(height: 16),
                      if (!_sent) ...[
                        const Text(
                          'Reset your password',
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Enter your account email and we'll send you a link to verify it's you and reset your password.",
                          style: TextStyle(fontSize: 13.5, color: Colors.black54, height: 1.4),
                        ),
                        const SizedBox(height: 20),
                        const Text('Email Address', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _emailController,
                          autofocus: true,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _decoration('you@example.com', Icons.email_outlined),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _sending ? null : _sendResetLink,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _dark,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                            child: _sending
                                ? const SizedBox(
                                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Send Reset Link', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ] else ...[
                        const Center(
                          child: Icon(Icons.mark_email_read_outlined, size: 56, color: _dark),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Check your email',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'We sent a verification link to ${_emailController.text.trim()}. '
                          'Open it to confirm it\'s you and set a new password.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13.5, color: Colors.black54, height: 1.4),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _dark,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                            child: const Text('Back to Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Floating back arrow, top-left. This form is short enough to
            // never need scrolling, so — unlike Register — it never needs a
            // backdrop behind it.
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: _dark),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
