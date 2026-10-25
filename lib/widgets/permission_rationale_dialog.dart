import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'agri_dialog.dart';

const _messageStyle = TextStyle(
  fontFamily: 'Montserrat',
  fontSize: 13.5,
  fontWeight: FontWeight.w500,
  color: Colors.black87,
  height: 1.5,
);

const _bulletStyle = TextStyle(
  fontFamily: 'Montserrat',
  fontSize: 12.5,
  fontWeight: FontWeight.w500,
  color: Colors.black87,
  height: 1.45,
);

/// A short "here's why we're about to ask" dialog, shown right before an OS
/// permission prompt — so the system dialog never appears out of nowhere.
/// [bullets], when given, are rendered as a left-aligned list in a soft green
/// panel below the (justified) [message] — used for the notification
/// examples list and the extra location-privacy disclosures. Returns true if the user chose to
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
  final result = await showAgriDialog<bool>(
    context: context,
    builder: (context) => AgriDialog(
      icon: icon,
      // The bundled Montserrat, so the title is truly bold.
      title: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppTheme.dark,
        ),
      ),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Justified beside a list of details; a short message on its own
          // is centred, where justifying would leave wide gaps.
          Text(
            message,
            textAlign: (bullets?.isNotEmpty ?? false)
                ? TextAlign.justify
                : TextAlign.center,
            style: _messageStyle,
          ),
          if (bullets != null && bullets.isNotEmpty) ...[
            const SizedBox(height: 14),
            // The details, in a soft green panel: each point with a small
            // green check, left-aligned and justified.
            Container(
              padding: const EdgeInsets.fromLTRB(10, 12, 12, 4),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.32),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: 0.9),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final b in bullets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1, right: 7),
                            child: Icon(
                              Icons.check_circle_rounded,
                              size: 15,
                              color: AppTheme.mid,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              b,
                              textAlign: TextAlign.justify,
                              style: _bulletStyle,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
      // Side by side ("Not Now" | "Allow") when both fit on one line,
      // else stacked with the main choice on top — see AgriDialog.
      actions: [
        AgriDialogButton(
          label: denyLabel,
          onPressed: () => Navigator.pop(context, false),
        ),
        AgriDialogButton(
          label: allowLabel,
          kind: AgriButtonKind.primary,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  return result ?? false;
}
