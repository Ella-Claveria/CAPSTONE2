import '../theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/message_search_history_service.dart';
import '../services/message_service.dart';
import '../widgets/profile_avatar.dart';
import 'chat_navigation.dart';

/// The dedicated Messages search experience — opened by tapping the (non-
/// editable) search bar on the Messages tab. Same screen for Farmer and
/// Buyer: this user's own recent searches while the field is empty, and
/// live matching conversations once they type.
class MessageSearchScreen extends StatefulWidget {
  const MessageSearchScreen({super.key});

  @override
  State<MessageSearchScreen> createState() => _MessageSearchScreenState();
}

class _MessageSearchScreenState extends State<MessageSearchScreen> {
  static const Color _dark = AppTheme.dark;
  static const Color _bg = Colors.white;
  static const Color _fieldFill = Color(0xFFF3F6F2);

  final MessageService _messageService = MessageService();
  final MessageSearchHistoryService _historyService =
      MessageSearchHistoryService();
  final TextEditingController _controller = TextEditingController();
  final String? _myUid = FirebaseAuth.instance.currentUser?.uid;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _conversations =
      _messageService.myConversationsStream();

  String _query = '';
  List<String> _recentSearches = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final next = _controller.text.trim().toLowerCase();
      if (next != _query) setState(() => _query = next);
    });
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final uid = _myUid;
    if (uid == null) return;
    final history = await _historyService.load(uid);
    if (!mounted) return;
    setState(() => _recentSearches = history);
  }

  // Saves ONE meaningful search — called on submit or when a result is
  // opened, never on every keystroke.
  Future<void> _saveSearch() async {
    final uid = _myUid;
    final term = _controller.text.trim();
    if (uid == null || term.isEmpty) return;
    final history = await _historyService.add(uid, term);
    if (!mounted) return;
    setState(() => _recentSearches = history);
  }

  void _useRecent(String term) {
    _controller.text = term;
    _controller.selection = TextSelection.collapsed(offset: term.length);
    _saveSearch();
  }

  Future<void> _removeRecent(String term) async {
    final uid = _myUid;
    if (uid == null) return;
    final history = await _historyService.remove(uid, term);
    if (!mounted) return;
    setState(() => _recentSearches = history);
  }

  Future<void> _clearRecent() async {
    final uid = _myUid;
    if (uid == null) return;
    await _historyService.clear(uid);
    if (!mounted) return;
    setState(() => _recentSearches = []);
  }

  String _otherUid(Map<String, dynamic> data) {
    final participants = List<dynamic>.from(data['participants'] ?? []);
    return participants
        .firstWhere((id) => id != _myUid, orElse: () => '')
        .toString();
  }

  String _otherName(Map<String, dynamic> data) {
    final names = Map<String, dynamic>.from(data['participantNames'] ?? {});
    return names[_otherUid(data)]?.toString() ?? 'User';
  }

  bool _matches(Map<String, dynamic> data, String term) {
    final needle = term.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return _otherName(data).toLowerCase().contains(needle) ||
        (data['lastMessage']?.toString() ?? '').toLowerCase().contains(
          needle,
        ) ||
        (data['productName']?.toString() ?? '').toLowerCase().contains(needle);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: _dark),
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _saveSearch(),
            decoration: InputDecoration(
              hintText: 'Search conversations...',
              hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: Colors.grey[500],
                size: 21,
              ),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.close,
                        color: Colors.grey[500],
                        size: 20,
                      ),
                      onPressed: _controller.clear,
                    )
                  : null,
              filled: true,
              fillColor: _fieldFill,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 4,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              constraints: const BoxConstraints(minHeight: 42, maxHeight: 42),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _conversations,
        builder: (context, snapshot) {
          final docs =
              (snapshot.data?.docs ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                  // Same rule as the Messages list: real threads only.
                  .where(
                    (doc) => _messageService.hasMessageActivity(
                      doc.id,
                      doc.data(),
                      onResolved: () {
                        if (mounted) setState(() {});
                      },
                    ),
                  )
                  .toList()
                ..sort((a, b) {
                  final at = a.data()['lastMessageTime'] as Timestamp?;
                  final bt = b.data()['lastMessageTime'] as Timestamp?;
                  return (bt?.millisecondsSinceEpoch ?? 0).compareTo(
                    at?.millisecondsSinceEpoch ?? 0,
                  );
                });

          if (_query.isNotEmpty) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _dark),
              );
            }
            final results = docs
                .where((doc) => _matches(doc.data(), _query))
                .toList();
            if (results.isEmpty) return _noResults();
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                for (final doc in results) _resultTile(doc.id, doc.data()),
              ],
            );
          }

          // Empty field: this user's recent searches, plus the
          // conversations those searches match.
          final fromRecent = docs
              .where(
                (doc) =>
                    _recentSearches.any((term) => _matches(doc.data(), term)),
              )
              .toList();

          if (_recentSearches.isEmpty) return _noHistory();

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              Row(
                children: [
                  Expanded(child: _sectionHeading('Recent searches')),
                  TextButton(
                    onPressed: _clearRecent,
                    style: TextButton.styleFrom(
                      foregroundColor: _dark,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(
                      'Clear all',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
              for (final term in _recentSearches) _recentTile(term),
              if (fromRecent.isNotEmpty) ...[
                const SizedBox(height: 16),
                _sectionHeading('From your recent searches'),
                const SizedBox(height: 8),
                for (final doc in fromRecent) _resultTile(doc.id, doc.data()),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeading(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _recentTile(String term) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _useRecent(term),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Row(
          children: [
            Icon(Icons.history, size: 20, color: Colors.grey[500]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                term,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 18, color: Colors.grey[500]),
              onPressed: () => _removeRecent(term),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultTile(String conversationId, Map<String, dynamic> data) {
    final otherUid = _otherUid(data);
    final fallbackName = _otherName(data);
    final lastMessage = data['lastMessage']?.toString() ?? '';
    final youSent = data['lastSenderId']?.toString() == _myUid;
    final preview = lastMessage.isEmpty
        ? 'Say hello 👋'
        : '${youSent ? 'You: ' : ''}$lastMessage';

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: otherUid.isEmpty
          ? null
          : FirebaseFirestore.instance
                .collection('publicProfiles')
                .doc(otherUid)
                .snapshots(),
      builder: (context, snapshot) {
        final profile = snapshot.data?.data();
        final profileName = profile?['name']?.toString().trim();
        final name = profileName != null && profileName.isNotEmpty
            ? profileName
            : fallbackName;
        final photoUrl = profile?['photoUrl']?.toString();

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              _saveSearch();
              openConversation(
                context,
                conversationId: conversationId,
                data: data,
                myUid: _myUid,
                otherUid: otherUid,
                otherName: name,
                otherPhotoUrl: photoUrl,
              );
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  ProfileAvatar(photoUrl: photoUrl, name: name, radius: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _noHistory() {
    return _centeredState(
      Icons.history,
      'No recent searches yet',
      'Search by name, message, or product.',
    );
  }

  Widget _noResults() {
    return _centeredState(
      Icons.search_off,
      'No matches for "${_controller.text.trim()}"',
      'Try a different name or keyword.',
    );
  }

  Widget _centeredState(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}
