import 'package:flutter/material.dart';

/// Shown instead of the app whenever a real internet connection could not
/// be confirmed — at launch (see AppBootstrap) and any time a routing
/// decision can't be verified live. Deliberately has no way to reach
/// Login, Farmer/Buyer Home, or the Admin Dashboard except by tapping
/// Retry and having it succeed.
class NoInternetScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final bool checking;

  const NoInternetScreen({
    super.key,
    required this.message,
    required this.onRetry,
    this.checking = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 72, color: Color(0xFF2E7D32)),
                const SizedBox(height: 20),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, height: 1.4, color: Colors.black87),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: checking ? null : onRetry,
                    icon: checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: Text(checking ? 'Checking…' : 'Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
