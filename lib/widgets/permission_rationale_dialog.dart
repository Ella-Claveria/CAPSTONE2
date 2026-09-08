import 'package:flutter/material.dart';

/// A short "here's why we're about to ask" dialog, shown right before an OS
/// permission prompt — so the system dialog never appears out of nowhere.
/// Returns true if the user chose to continue (caller should then trigger
/// the actual OS permission request), false if they dismissed/declined.
Future<bool> showPermissionRationale(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      icon: Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(color: Color(0xFFDCEDC8), shape: BoxShape.circle),
        child: Icon(icon, color: const Color(0xFF1B5E20), size: 28),
      ),
      title: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
      content: Text(message, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now', style: TextStyle(color: Colors.black54)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1B5E20),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  return result ?? false;
}
