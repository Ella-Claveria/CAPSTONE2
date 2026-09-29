import 'package:flutter/material.dart';

/// A short "here's why we're about to ask" dialog, shown right before an OS
/// permission prompt — so the system dialog never appears out of nowhere.
/// [bullets], when given, are rendered as a left-aligned list below the main
/// (centered) [message] — used for the notification examples list and the
/// extra location-privacy disclosures. Returns true if the user chose to
/// continue (caller should then trigger the actual OS permission request),
/// false if they dismissed/declined.
Future<bool> showPermissionRationale(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  List<String>? bullets,
  String denyLabel = 'Not now',
  String allowLabel = 'Continue',
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
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (bullets != null && bullets.isNotEmpty) ...[
              const SizedBox(height: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: bullets
                    .map((b) => Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 5, right: 8),
                                child: Icon(Icons.circle, size: 5, color: Colors.black45),
                              ),
                              Expanded(
                                child: Text(
                                  b,
                                  style: const TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(denyLabel, style: const TextStyle(color: Colors.black54)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1B5E20),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: Text(allowLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
