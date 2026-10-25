import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
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
    // This screen also appears when the app could not confirm an account
    // with Firebase. If the internet itself is known to be working, that
    // is a server problem, not the user being offline — so it says so
    // instead of telling them to check their Wi-Fi.
    final serverIssue = ConnectivityService.instance.lastKnownOnline == true;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 72,
                  color: AppTheme.dark,
                ),
                const SizedBox(height: 20),
                Text(
                  serverIssue ? 'Can\'t connect right now' : 'You\'re offline',
                  textAlign: TextAlign.center,
                  style: AppTheme.heading(20),
                ),
                const SizedBox(height: 10),
                Text(
                  serverIssue
                      ? 'Your internet is working, but AgriTrade+ could not '
                            'be reached.'
                      : message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  serverIssue
                      ? 'Please try again in a moment.'
                      : 'Check your Wi-Fi or mobile data, then try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.grey[600],
                  ),
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
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: Text(checking ? 'Checking…' : 'Try Again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.dark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: const StadiumBorder(),
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
