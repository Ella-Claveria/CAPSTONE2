import 'package:flutter/material.dart';

/// The very first thing Flutter draws after the native splash hands off —
/// kept pixel-identical to that native splash (same background, same
/// circular logo, nothing else moving) so the handoff between the two is
/// invisible — it just reads as one continuous splash screen.
class BrandedLoadingScreen extends StatelessWidget {
  const BrandedLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ClipOval(
          child: Image.asset(
            'assets/images/logo.png',
            width: 120,
            height: 120,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const Icon(Icons.agriculture, size: 60, color: Color(0xFF2E7D32)),
            ),
          ),
        ),
      ),
    );
  }
}
