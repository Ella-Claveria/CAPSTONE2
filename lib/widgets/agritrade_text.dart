import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../screen/admin_dashboard_screen.dart'; // Make sure to import the dashboard

// Reusable "AgriTrade+" wordmark: "Agri" #2D392B, "Trade+" #7E5D09.
class AgriTradeText extends StatelessWidget {
  final double fontSize;
  const AgriTradeText({super.key, this.fontSize = 28});

  static const Color _agri = Color.fromARGB(255, 14, 50, 16);
  static const Color _trade = Color(0xFF7E5D09);

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.lilitaOne(fontSize: fontSize),
        children: const [
          TextSpan(text: 'Agri', style: TextStyle(color: _agri)),
          TextSpan(text: 'Trade+', style: TextStyle(color: _trade)),
        ],
      ),
    );
  }
}

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _loginAdmin() async {
    setState(() => _isLoading = true);
    try {
      // 1. Authenticate with Firebase
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim());

      // 2. Verify Admin Role in Firestore
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data() as Map<String, dynamic>;
        if (data['role'] == 'admin') {
          // Success: Navigate to Admin Dashboard
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => AdminDashboardScreen()),
            );
          }
          return;
        }
      }
      
      // If not admin, sign out and show error
      await FirebaseAuth.instance.signOut();
      _showError('Access Denied: Admin privileges required.');

    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Login failed. Please check your credentials.');
    } catch (e) {
      _showError('An unexpected error occurred.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)), 
        backgroundColor: Colors.red
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], 
      body: Row(
        children: [
          // ==========================================
          // LEFT SIDE: Image Placeholder
          // ==========================================
          Expanded(
            flex: 1, 
            child: Container(
              color: Colors.grey[300], 
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image, size: 80, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'Insert Image Here',
                      style: TextStyle(color: Colors.black54, fontSize: 18),
                    ),
                  ],
                ),
               
                // child: Image.asset('assets/images/your_image.png', fit: BoxFit.cover),
              ),
            ),
          ),

          // ==========================================
          // RIGHT SIDE: Login Form
          // ==========================================
          Expanded(
            flex: 1,
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  width: 380, 
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12, 
                        blurRadius: 15, 
                        offset: Offset(0, 5)
                      )
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Integrated custom AgriTradeText widget
                      Center(
                        child: Column(
                          children: [
                            const AgriTradeText(fontSize: 36), // Using your custom widget
                            const SizedBox(height: 4),
                            Text(
                              'Admin Portal', 
                              style: TextStyle(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500)
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Username Field
                      Text('Username', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          hintText: 'admin.username',
                          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                          prefixIcon: Icon(Icons.mail_outline, size: 20, color: Colors.grey[600]),
                          filled: true,
                          fillColor: Colors.grey[200],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Password Field with Forgot Password Label
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: () {
                                // Add forgot password logic here
                              },
                              child: Text(
                                'Forgot Password?', 
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue[600])
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          hintText: '••••••••',
                          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                          prefixIcon: Icon(Icons.lock_outline, size: 20, color: Colors.grey[600]),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off : Icons.visibility,
                              size: 20,
                              color: Colors.grey[600],
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          filled: true,
                          fillColor: Colors.grey[200],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Login Button
                      _isLoading 
                        ? Center(child: CircularProgressIndicator(color: Colors.green[800]))
                        : ElevatedButton.icon(
                            onPressed: _loginAdmin,
                            icon: const Icon(Icons.login, size: 18, color: Colors.white),
                            label: const Text('Log In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[800],
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              elevation: 0,
                            ),
                          ),
                      const SizedBox(height: 24),

                      // Footer elements
                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shield_outlined, size: 14, color: Colors.grey[500]),
                            const SizedBox(width: 6),
                            Text(
                              'Secure Admin Connection',
                              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 48),
                      Center(
                        child: Text(
                          '© 2026 AgriTrade+',
                          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}