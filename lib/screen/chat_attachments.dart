import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../services/location_permission_prompt.dart';
import '../theme/app_theme.dart';
import '../widgets/agri_dialog.dart';

// The chat composer and its attachment menu, shared by the Farmer and Buyer
// chat screens (ChatScreen and MessageOrderScreen).
//
// Permissions are asked only when an attachment is actually used — never
// at startup or onboarding:
//  - Camera / photos: the system asks the first time (iOS); Android's
//    camera hand-off and photo picker need no runtime permission at all.
//    Once granted it's never asked again. If access is denied, the user
//    gets an explanation with Try Again / Open Settings.
//  - Location: separate, requested only after the user confirms Share
//    Location, and never sent automatically.

enum ChatAttachment { camera, gallery, location }

/// The + menu: Camera, Choose Photo, Share Location — a small floating menu
/// that opens upward from the + button ([plusButtonContext]).
Future<ChatAttachment?> showChatAttachmentMenu(BuildContext plusButtonContext) {
  return showAgriPopupMenu<ChatAttachment>(
    anchorContext: plusButtonContext,
    upward: true,
    width: 196,
    items: const [
      AgriMenuItem(
        value: ChatAttachment.camera,
        icon: Icons.camera_alt_outlined,
        label: 'Camera',
      ),
      AgriMenuItem(
        value: ChatAttachment.gallery,
        icon: Icons.photo_library_outlined,
        label: 'Choose Photo',
      ),
      AgriMenuItem(
        value: ChatAttachment.location,
        icon: Icons.location_on_outlined,
        label: 'Share Location',
      ),
    ],
  );
}

/// Takes or picks one photo for a chat message. Null if the user cancelled
/// or access was denied (after explaining how to allow it).
Future<XFile?> pickChatPhoto(BuildContext context, ImageSource source) async {
  final camera = source == ImageSource.camera;
  while (true) {
    try {
      return await ImagePicker().pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 70,
      );
    } on PlatformException catch (e) {
      if (!context.mounted) return null;
      final denied =
          e.code.contains('access_denied') ||
          e.code.contains('access_restricted');
      if (!denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              camera
                  ? 'The camera isn\'t available right now.'
                  : 'Your photos couldn\'t be opened right now.',
            ),
          ),
        );
        return null;
      }
      final retry = await _explainMediaDenied(context, camera: camera);
      if (!retry || !context.mounted) return null;
    }
  }
}

/// Access was denied: says why it's needed and how to allow it. True means
/// try again.
Future<bool> _explainMediaDenied(
  BuildContext context, {
  required bool camera,
}) async {
  final action = await showAgriDialog<String>(
    context: context,
    builder: (dialogContext) => AgriDialog(
      icon: camera ? Icons.no_photography_outlined : Icons.hide_image_outlined,
      tone: AgriTone.warning,
      title: Text(camera ? 'Camera access is off' : 'Photo access is off'),
      content: Text(
        camera
            ? 'AgriTrade+ needs the camera to take a photo to send in this '
                  'chat. Allow camera access in your device settings, then '
                  'try again.'
            : 'AgriTrade+ needs access to your photos to send one in this '
                  'chat. Allow photo access in your device settings, then '
                  'try again.',
      ),
      actions: [
        AgriDialogButton(
          label: 'Try Again',
          onPressed: () => Navigator.pop(dialogContext, 'retry'),
        ),
        AgriDialogButton(
          label: 'Open Settings',
          kind: AgriButtonKind.primary,
          onPressed: () => Navigator.pop(dialogContext, 'settings'),
        ),
      ],
    ),
  );
  if (action == 'settings') {
    await Geolocator.openAppSettings();
    return false;
  }
  return action == 'retry';
}

/// Share Location, step by step: confirm (exact location, this chat only,
/// for delivery/pick-up) → location permission (asked only now) → location
/// services on → current position. Null if the user stopped at any step or
/// it couldn't be read; nothing is ever sent without the confirmation.
Future<Position?> getLocationToShare(
  BuildContext context, {
  required String otherUserName,
}) async {
  final confirmed = await showAgriConfirm(
    context: context,
    icon: Icons.location_on_outlined,
    title: 'Share your exact location?',
    message:
        'Your current location will be sent to $otherUserName in this chat '
        'only — use it to coordinate delivery or pick-up. Your public '
        'profile still shows only your general area.',
    confirmLabel: 'Share Location',
  );
  if (!confirmed || !context.mounted) return null;

  final granted = await maybeRequestLocationPermission(
    context,
    title: 'Share your location',
    message:
        'AgriTrade+ needs location access to send your current position in '
        'this chat. It\'s only read when you choose Share Location.',
  );
  if (!granted || !context.mounted) return null;

  if (!await Geolocator.isLocationServiceEnabled()) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Turn on location services to share your location.'),
      ),
    );
    return null;
  }

  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );
}

/// Thin bar at the top of the messages area while a conversation's first
/// batch of messages loads. The rest of the chat stays on screen.
class ChatMessagesLoadingBar extends StatelessWidget {
  const ChatMessagesLoadingBar({super.key});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(48, 8, 48, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          minHeight: 2.5,
          color: AppTheme.dark.withValues(alpha: 0.55),
          backgroundColor: AppTheme.dark.withValues(alpha: 0.08),
        ),
      ),
    ),
  );
}

/// The message box: one + button for attachments, a wide text field that
/// grows as the user types more lines, and Send.
class ChatComposerBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool sending;
  final VoidCallback onSend;

  /// Called with the + button's context, to anchor the attachment menu.
  final ValueChanged<BuildContext> onAttach;

  const ChatComposerBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.sending,
    required this.onSend,
    required this.onAttach,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Builder(
          builder: (buttonContext) => IconButton(
            tooltip: 'Attach',
            onPressed: sending ? null : () => onAttach(buttonContext),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 42),
            padding: EdgeInsets.zero,
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              color: AppTheme.dark,
              size: 26,
            ),
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: hintText,
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF4F6F2),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 11,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: sending ? Colors.grey[400] : AppTheme.dark,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: sending ? null : onSend,
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 42,
              height: 42,
              child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}
