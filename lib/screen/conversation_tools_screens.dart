import '../widgets/agri_app_bar.dart';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../widgets/app_search_bar.dart';
import '../widgets/agri_empty_state.dart';

// Conversation tools opened from Conversation Info, shared by the Farmer
// and Buyer chats:
//  - ConversationSearchScreen: searches this conversation's messages only;
//    picking a result returns its message id so the chat jumps to it.
//  - ConversationPhotosScreen: every photo shared in the conversation, with
//    a full-screen, zoomable preview.
//  - MessageJumpTargets: what lets a chat scroll to (and briefly highlight)
//    one message.

Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadMessages(
  String conversationId,
) async {
  final snap = await FirebaseFirestore.instance
      .collection('conversations')
      .doc(conversationId)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .get();
  return snap.docs;
}

String _formatDate(BuildContext context, Timestamp? ts) {
  if (ts == null) return '';
  final date = ts.toDate();
  final now = DateTime.now();
  final time = TimeOfDay.fromDateTime(date).format(context);
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return time;
  }
  return '${MaterialLocalizations.of(context).formatMediumDate(date)}, $time';
}

/// Lets a chat's message list jump to one message: each message is wrapped
/// with [wrap], and [jumpTo] scrolls the (reversed) list until that message
/// is built, centres it and highlights it for a moment.
///
/// No GlobalKeys: each wrapped message registers its own BuildContext while
/// it's mounted and removes it when it's disposed. (GlobalKeys on lazily
/// built list items tripped Flutter's element bookkeeping — the
/// "_elements.contains(element)" assertion — when the chat route was
/// covered and uncovered by Conversation Info.)
class MessageJumpTargets {
  final Map<String, BuildContext> _mounted = {};
  final ValueNotifier<String?> _highlighted = ValueNotifier<String?>(null);
  bool _disposed = false;

  Widget wrap(String messageId, Widget child) => _JumpTarget(
    key: ValueKey('jump-$messageId'),
    messageId: messageId,
    targets: this,
    child: child,
  );

  void _register(String messageId, BuildContext context) {
    _mounted[messageId] = context;
  }

  void _unregister(String messageId, BuildContext context) {
    // Only if it's still this element's entry (a rebuilt item may already
    // have registered a newer one).
    if (identical(_mounted[messageId], context)) _mounted.remove(messageId);
  }

  /// Scrolls to [messageId]. The list builds lazily, so it starts from the
  /// newest message and moves back a screen at a time until the message
  /// has been built. Returns false if it couldn't be found.
  Future<bool> jumpTo(ScrollController controller, String messageId) async {
    if (_disposed || !controller.hasClients) return false;
    controller.jumpTo(0);
    for (var step = 0; step < 200; step++) {
      await WidgetsBinding.instance.endOfFrame;
      if (_disposed) return false;
      final context = _mounted[messageId];
      if (context != null && context.mounted) {
        await Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 300),
        );
        if (_disposed) return false;
        _highlighted.value = messageId;
        Future.delayed(const Duration(seconds: 2), () {
          if (!_disposed && _highlighted.value == messageId) {
            _highlighted.value = null;
          }
        });
        return true;
      }
      if (!controller.hasClients) return false;
      final position = controller.position;
      if (position.pixels >= position.maxScrollExtent) return false;
      controller.jumpTo(
        math.min(
          position.pixels + position.viewportDimension * 0.8,
          position.maxScrollExtent,
        ),
      );
    }
    return false;
  }

  void dispose() {
    _disposed = true;
    _mounted.clear();
    _highlighted.dispose();
  }
}

class _JumpTarget extends StatefulWidget {
  final String messageId;
  final MessageJumpTargets targets;
  final Widget child;

  const _JumpTarget({
    super.key,
    required this.messageId,
    required this.targets,
    required this.child,
  });

  @override
  State<_JumpTarget> createState() => _JumpTargetState();
}

class _JumpTargetState extends State<_JumpTarget> {
  @override
  void initState() {
    super.initState();
    widget.targets._register(widget.messageId, context);
  }

  @override
  void didUpdateWidget(_JumpTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messageId != widget.messageId) {
      oldWidget.targets._unregister(oldWidget.messageId, context);
      widget.targets._register(widget.messageId, context);
    }
  }

  @override
  void dispose() {
    widget.targets._unregister(widget.messageId, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.targets._disposed) return widget.child;
    return ValueListenableBuilder<String?>(
      valueListenable: widget.targets._highlighted,
      builder: (context, highlighted, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: highlighted == widget.messageId
              ? const Color(0xFFFFF3C4)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Search inside one conversation. Pops with the chosen message's id.
class ConversationSearchScreen extends StatefulWidget {
  final String conversationId;

  /// The other person's name as shown in this conversation (their nickname
  /// here, if set).
  final String otherDisplayName;

  const ConversationSearchScreen({
    super.key,
    required this.conversationId,
    required this.otherDisplayName,
  });

  @override
  State<ConversationSearchScreen> createState() =>
      _ConversationSearchScreenState();
}

class _ConversationSearchScreenState extends State<ConversationSearchScreen> {
  final _query = TextEditingController();
  late final Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _messages = _loadMessages(widget.conversationId);
  final String? _myUid = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AgriAppBar(
        titleWidget: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: AppSearchBar(
            hint: 'Search this conversation',
            controller: _query,
            autofocus: true,
            onClear: _query.clear,
          ),
        ),
      ),
      body: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        future: _messages,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _hint('Couldn\'t load messages. Check your connection.');
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.dark),
            );
          }
          final query = _query.text.trim().toLowerCase();
          if (query.isEmpty) {
            return _hint(
              'Search for words in your messages with '
              '${widget.otherDisplayName}.',
            );
          }
          final results = snapshot.data!
              .where(
                (doc) => (doc.data()['text'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(query),
              )
              .toList();
          if (results.isEmpty) return _hint('No messages match "$query".');
          return ListView.separated(
            itemCount: results.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final data = results[i].data();
              final mine = data['senderId'] == _myUid;
              return ListTile(
                title: _highlightedText(data['text'].toString(), query),
                subtitle: Text(
                  '${mine ? 'You' : widget.otherDisplayName} · '
                  '${_formatDate(context, data['createdAt'] as Timestamp?)}',
                  style: GoogleFonts.montserrat(
                    fontSize: 11.5,
                    color: Colors.grey[600],
                  ),
                ),
                onTap: () => Navigator.pop(context, results[i].id),
              );
            },
          );
        },
      ),
    );
  }

  Widget _hint(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.montserrat(fontSize: 13, color: Colors.grey[600]),
      ),
    ),
  );

  // The message with every match in bold.
  Widget _highlightedText(String text, String query) {
    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final index = lower.indexOf(query, start);
      if (index < 0) break;
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.dark,
          ),
        ),
      );
      start = index + query.length;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
    return Text.rich(
      TextSpan(
        style: GoogleFonts.montserrat(fontSize: 13.5, color: Colors.black87),
        children: spans,
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Every photo shared in one conversation, newest first.
class ConversationPhotosScreen extends StatefulWidget {
  final String conversationId;
  final String otherDisplayName;

  const ConversationPhotosScreen({
    super.key,
    required this.conversationId,
    required this.otherDisplayName,
  });

  @override
  State<ConversationPhotosScreen> createState() =>
      _ConversationPhotosScreenState();
}

class _ConversationPhotosScreenState extends State<ConversationPhotosScreen> {
  // Loaded once — not re-fetched on every rebuild.
  late final Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _messages = _loadMessages(widget.conversationId);

  String get otherDisplayName => widget.otherDisplayName;

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const AgriAppBar(title: 'Photos'),
      body: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        future: _messages,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Couldn\'t load photos. Check your connection.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.dark),
            );
          }
          final photos = snapshot.data!
              .where(
                (doc) => (doc.data()['imageUrl'] ?? '').toString().isNotEmpty,
              )
              .toList();
          if (photos.isEmpty) {
            return Center(
              child: AgriEmptyState(
                icon: Icons.photo_library_outlined,
                title: 'No photos yet',
                subtitle:
                    'Photos you and $otherDisplayName send will appear here.',
                padding: const EdgeInsets.all(32),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: photos.length,
            itemBuilder: (context, i) {
              final data = photos[i].data();
              final url = data['imageUrl'].toString();
              final caption =
                  '${data['senderId'] == myUid ? 'You' : otherDisplayName} · '
                  '${_formatDate(context, data['createdAt'] as Timestamp?)}';
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _PhotoPreview(url: url, caption: caption),
                  ),
                ),
                child: Hero(
                  tag: url,
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: Colors.grey.shade200,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// A shared photo, full screen; pinch to zoom.
class _PhotoPreview extends StatelessWidget {
  final String url;
  final String caption;

  const _PhotoPreview({required this.url, required this.caption});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          caption,
          style: GoogleFonts.montserrat(fontSize: 13, color: Colors.white70),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Hero(
            tag: url,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const CircularProgressIndicator(color: Colors.white),
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
