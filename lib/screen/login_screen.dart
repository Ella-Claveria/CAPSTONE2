import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'register_screen.dart';
import 'farmer_home_screen.dart';
import 'buyer_marketplace_screen.dart';
import '../widgets/agritrade_text.dart';
import 'admin_dashboard_screen.dart';
import '../widgets/role_mismatch_dialog.dart';


class LoginScreen extends StatefulWidget {
  final String role;
  const LoginScreen({super.key, required this.role});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _loading = false;
  bool _obscurePassword = true;

  bool get _isFarmer => widget.role == 'farmer';
  bool get _isAdmin => widget.role == 'admin';

  // Human-readable label for the role subtitle under the AgriTrade+ logo.
  String get _roleLabel {
    if (_isAdmin) return 'Admin Login';
    if (_isFarmer) return 'Farmer Login';
    return 'Buyer Login';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showMessage('Please enter your email and password.');
      return;
    }
    setState(() => _loading = true);
    final error = await _authService.logIn(
      email: email,
      password: password,
      expectedRole: widget.role,
    );
    if (!mounted) return;

     if (error != null && error.startsWith('ROLE_MISMATCH:')) {
      final registeredRole = error.substring('ROLE_MISMATCH:'.length);
      showRoleMismatchDialog(context, registeredRole);
      return;
    }

    setState(() => _loading = false);
    if (error == null) {
      // pushAndRemoveUntil clears splash/role-selection/login from the stack,
      // so the back button on Home has nothing left to pop to.
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) {
            if (_isAdmin) return AdminDashboardScreen();
            if (_isFarmer) return FarmerHomeScreen();
            return const BuyerMarketplaceScreen();
          },
        ),
        (route) => false,
      );
    } else {
      _showMessage(error);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // ===== Background image (with green fallback) =====
        decoration: const BoxDecoration(
          color: Color(0xFF1B5E20),
          image: DecorationImage(
            image: AssetImage('assets/background_login.png'),
            fit: BoxFit.cover,
            onError: null,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                // ===== Frosted white card =====
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 8)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Back button inside the card
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.arrow_back, color: Color(0xFF1B5E20)),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Image.asset(
                        'assets/logo.png',
                        width: 80,
                        height: 80,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 80,
                            height: 80,
                            decoration: const BoxDecoration(color: Color(0xFF2E7D32), shape: BoxShape.circle),
                            child: const Icon(Icons.agriculture, size: 42, color: Colors.white),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Center(child: Text('Welcome to', style: TextStyle(fontSize: 20, color: Colors.black87))),
                    const Center(child: AgriTradeText(fontSize: 30)),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(_roleLabel,
                          style: const TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(height: 24),
                    const Text('Email Address', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'you@example.com',
                        filled: true,
                        fillColor: const Color(0xFFF2F2F2),
                        suffixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Password', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('Forgot Password?', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        hintText: 'Password',
                        filled: true,
                        fillColor: const Color(0xFFF2F2F2),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey[600]),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B5E20),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: _loading
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // The "Sign up" link makes no sense for admin accounts —
                    // DA officers are created manually via Firebase Console,
                    // not via self-registration. So we hide it for admin.
                    if (!_isAdmin)
                      Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.push(context,
                                MaterialPageRoute(builder: (_) => RegisterScreen(role: widget.role)));
                          },
                          child: RichText(
                            text: const TextSpan(
                              style: TextStyle(color: Colors.black87),
                              children: [
                                TextSpan(text: "Don't have an account? "),
                                TextSpan(text: 'Sign up', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}