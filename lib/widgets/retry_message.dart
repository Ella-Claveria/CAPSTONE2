import 'package:flutter/material.dart';

/// Compact inline error state for data streams that can be restarted by
/// rebuilding their owning screen.
class RetryMessage extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const RetryMessage({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ]),
        ),
      );
}
