import 'package:shared_preferences/shared_preferences.dart';

/// Recent searches for the Messages search screen, stored on this device
/// and keyed by uid so each account only ever sees its own history.
class MessageSearchHistoryService {
  static const int _maxEntries = 8;

  static String _key(String uid) => 'message_search_history_$uid';

  Future<List<String>> load(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key(uid)) ?? <String>[];
  }

  /// Puts [query] at the top of the history, dropping any older duplicate.
  Future<List<String>> add(String uid, String query) async {
    final term = query.trim();
    if (term.isEmpty) return load(uid);
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_key(uid)) ?? <String>[];
    history.removeWhere((item) => item.toLowerCase() == term.toLowerCase());
    history.insert(0, term);
    final trimmed = history.take(_maxEntries).toList();
    await prefs.setStringList(_key(uid), trimmed);
    return trimmed;
  }

  Future<List<String>> remove(String uid, String query) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_key(uid)) ?? <String>[];
    history.remove(query);
    await prefs.setStringList(_key(uid), history);
    return history;
  }

  Future<void> clear(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(uid));
  }
}
