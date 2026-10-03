import 'package:flutter/material.dart';
import 'chat_list_screen.dart';
import 'message_management_screens.dart';

/// The Archived folder, opened from Archived in the Messages menu. Same
/// screen for Farmer and Buyer — it is the Messages list itself in its
/// archived mode, so rows look and behave exactly like the inbox
/// (long-press a chat to unarchive it).
class ArchivedConversationsScreen extends StatelessWidget {
  const ArchivedConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const MessageFolderScaffold(
      title: 'Archived',
      body: ChatListScreen(mode: ChatListMode.archived),
    );
  }
}
