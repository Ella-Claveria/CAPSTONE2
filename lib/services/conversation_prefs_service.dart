import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which conversations the signed-in user has pinned, muted or archived,
/// and which users they have blocked. Stored on this device and keyed by
/// uid, so each account only ever sees its own choices. One shared
/// instance, so the inbox and the Archived/Muted/Blocked screens agree.
class ConversationPrefs extends ChangeNotifier {
  ConversationPrefs._();
  static final ConversationPrefs instance = ConversationPrefs._();

  String? _uid;
  final Set<String> _pinned = <String>{};
  final Set<String> _muted = <String>{};

  // User ids (not conversation ids) — blocking someone hides every
  // conversation with them, until they're unblocked.
  final Set<String> _blocked = <String>{};

  // conversationId -> the conversation's last-message time (ms) when it
  // was archived. A later incoming message is newer than this, which is
  // what moves the chat back to the inbox.
  final Map<String, int> _archived = <String, int>{};

  // conversationId -> the nickname this user gave the other person in that
  // one conversation. Display-only and on this device: the other person's
  // real account name is never changed, and every other screen (profile,
  // marketplace, orders, other chats, admin) keeps showing it.
  final Map<String, String> _nicknames = <String, String>{};

  Future<void> load(String? uid) async {
    if (uid == _uid) return;
    _uid = uid;
    _pinned.clear();
    _muted.clear();
    _archived.clear();
    _blocked.clear();
    _nicknames.clear();
    if (uid != null) {
      final prefs = await SharedPreferences.getInstance();
      if (_uid != uid) return; // Another account signed in meanwhile.
      _pinned.addAll(prefs.getStringList('conv_pinned_$uid') ?? const []);
      _muted.addAll(prefs.getStringList('conv_muted_$uid') ?? const []);
      _blocked.addAll(prefs.getStringList('conv_blocked_$uid') ?? const []);
      for (final entry
          in prefs.getStringList('conv_archived_$uid') ?? const <String>[]) {
        final split = entry.lastIndexOf('|');
        if (split <= 0) continue;
        _archived[entry.substring(0, split)] =
            int.tryParse(entry.substring(split + 1)) ?? 0;
      }
      // "conversationId|nickname" — conversation ids never contain '|',
      // so the first one splits it even if the nickname has one.
      for (final entry
          in prefs.getStringList('conv_nicknames_$uid') ?? const <String>[]) {
        final split = entry.indexOf('|');
        if (split <= 0 || split == entry.length - 1) continue;
        _nicknames[entry.substring(0, split)] = entry.substring(split + 1);
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final uid = _uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('conv_pinned_$uid', _pinned.toList());
    await prefs.setStringList('conv_muted_$uid', _muted.toList());
    await prefs.setStringList('conv_blocked_$uid', _blocked.toList());
    await prefs.setStringList('conv_archived_$uid', [
      for (final e in _archived.entries) '${e.key}|${e.value}',
    ]);
    await prefs.setStringList('conv_nicknames_$uid', [
      for (final e in _nicknames.entries) '${e.key}|${e.value}',
    ]);
  }

  static const int nicknameMaxLength = 40;

  /// The nickname set for [conversationId], or null.
  String? nicknameFor(String conversationId) => _nicknames[conversationId];

  /// What to call the other person inside [conversationId]: the nickname if
  /// one is set, otherwise [realName].
  String displayName(String conversationId, String realName) =>
      _nicknames[conversationId] ?? realName;

  /// Sets the nickname for one conversation; empty/blank removes it, so the
  /// real name shows again.
  void setNickname(String conversationId, String? nickname) {
    final trimmed = (nickname ?? '').trim();
    if (trimmed.isEmpty) {
      if (_nicknames.remove(conversationId) == null) return;
    } else {
      final value = trimmed.length > nicknameMaxLength
          ? trimmed.substring(0, nicknameMaxLength)
          : trimmed;
      if (_nicknames[conversationId] == value) return;
      _nicknames[conversationId] = value;
    }
    notifyListeners();
    _save();
  }

  bool isPinned(String id) => _pinned.contains(id);
  bool isMuted(String id) => _muted.contains(id);

  /// Whether [id] was archived at all, even if a newer message has since
  /// made it due to return to the inbox (see [isArchived]).
  bool hasArchiveEntry(String id) => _archived.containsKey(id);

  /// Archived, and no message from the other person has arrived since.
  bool isArchived(
    String id, {
    required int lastMessageMs,
    required bool lastFromOther,
  }) {
    final archivedAt = _archived[id];
    if (archivedAt == null) return false;
    return !(lastFromOther && lastMessageMs > archivedAt);
  }

  void togglePinned(String id) {
    if (!_pinned.add(id)) _pinned.remove(id);
    notifyListeners();
    _save();
  }

  void toggleMuted(String id) {
    if (!_muted.add(id)) _muted.remove(id);
    notifyListeners();
    _save();
  }

  void archive(String id, {required int lastMessageMs}) {
    _archived[id] = lastMessageMs;
    notifyListeners();
    _save();
  }

  void unarchive(String id) {
    if (_archived.remove(id) == null) return;
    notifyListeners();
    _save();
  }

  bool isBlocked(String userId) => _blocked.contains(userId);

  /// The blocked user ids, for the Blocked Users screen.
  List<String> get blockedUserIds => _blocked.toList();

  void block(String userId) {
    if (userId.isEmpty || !_blocked.add(userId)) return;
    notifyListeners();
    _save();
  }

  void unblock(String userId) {
    if (!_blocked.remove(userId)) return;
    notifyListeners();
    _save();
  }
}
