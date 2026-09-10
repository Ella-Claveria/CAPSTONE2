import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// AgriTrade+ depends on live Firebase data everywhere — farmer approval
/// status, inventory, orders, admin stats — so this app cannot work
/// meaningfully offline. "Online" here specifically means "can actually
/// reach Firebase right now", not just "has a Wi-Fi/cellular link": a
/// device can show full signal on a captive portal or a dead access point
/// and still have zero real connectivity, so every check below confirms
/// real reachability instead of trusting the network interface alone.
///
/// Reachability is confirmed with a forced-server read of `market_prices`
/// (`allow read: if true` in firestore.rules, so this works even before
/// sign-in) — never a bare cache read, since Firestore's on-device cache
/// would otherwise make the app look reachable while fully offline. This
/// is the single source of truth for connectivity across the app: the
/// splash gate, the in-app warning banner, and every guarded write all go
/// through this one instance so nothing spams Firebase with duplicate
/// checks.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  static const Duration _probeTimeout = Duration(seconds: 6);
  static const Duration _cacheTtl = Duration(seconds: 5);

  bool? _lastResult;
  DateTime? _lastCheckedAt;
  Future<bool>? _inFlight;
  bool _watching = false;
  StreamSubscription<List<ConnectivityResult>>? _netSub;

  final _statusController = StreamController<bool>.broadcast();

  /// The last confirmed result, or null if no check has completed yet.
  bool? get lastKnownOnline => _lastResult;

  /// Fires only on confirmed online/offline transitions while the app is
  /// running — used by the app-wide warning banner (requirement: warn
  /// immediately when connectivity drops mid-session, and let the app
  /// recover automatically once it returns).
  Stream<bool> get onStatusChanged => _statusController.stream;

  /// Starts the background watchdog once per app run. Listens to
  /// connectivity_plus for network *changes* (event-driven, no polling)
  /// and only spends a real Firebase probe when the raw network state
  /// actually changes — this can never turn into a spam loop.
  void startWatching() {
    if (_watching) return;
    _watching = true;
    _netSub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (!hasNetwork) {
        _setResult(false);
        return;
      }
      // The network link came back — confirm it's actually usable before
      // telling the rest of the app it's safe to resume online actions.
      checkNow(force: true);
    });
  }

  /// Not called during normal app life (this is a process-lifetime
  /// singleton) — provided for completeness/tests.
  void dispose() {
    _netSub?.cancel();
    _netSub = null;
    _watching = false;
  }

  void _setResult(bool online) {
    final changed = _lastResult != online;
    _lastResult = online;
    _lastCheckedAt = DateTime.now();
    if (changed) _statusController.add(online);
  }

  /// Confirms real reachability right now. A short cache avoids re-probing
  /// Firebase for calls made within a couple of seconds of each other
  /// (e.g. several guarded actions in a row); pass `force: true` to bypass
  /// it — the splash screen's Retry button always forces a fresh check.
  Future<bool> checkNow({bool force = false}) {
    if (!force && _lastResult != null && _lastCheckedAt != null) {
      if (DateTime.now().difference(_lastCheckedAt!) < _cacheTtl) {
        return Future.value(_lastResult);
      }
    }
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = _probe();
    _inFlight = future;
    future.whenComplete(() => _inFlight = null);
    return future;
  }

  Future<bool> _probe() async {
    try {
      final netResults = await Connectivity().checkConnectivity();
      if (netResults.every((r) => r == ConnectivityResult.none)) {
        _setResult(false);
        return false;
      }
    } catch (_) {
      // connectivity_plus unavailable on this platform/build — fall
      // through to the real Firebase probe below, which is authoritative
      // anyway.
    }

    try {
      await FirebaseFirestore.instance
          .collection('market_prices')
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(_probeTimeout);
      _setResult(true);
      return true;
    } catch (_) {
      _setResult(false);
      return false;
    }
  }
}

/// One-shot real connectivity + Firebase-reachability check. Prefer this in
/// simple call sites; screens that need to react to live changes should use
/// [ConnectivityService.instance.onStatusChanged] instead.
Future<bool> hasInternet() => ConnectivityService.instance.checkNow();

/// Checks reachability and returns a ready-to-show error message when
/// offline, or null when the caller is clear to proceed. Every write action
/// that must never be silently queued while offline (placing an order,
/// updating a product, approving/rejecting a farmer, changing an order's
/// status, an admin price/report action) calls this first.
Future<String?> requireOnlineOrError() async {
  final online = await ConnectivityService.instance.checkNow();
  return online ? null : kNoInternetActionMessage;
}

const String kNoInternetMessage = 'No internet connection. AgriTrade+ requires an '
    'active internet connection to access updated marketplace data.';

const String kNoInternetAdminMessage =
    'No internet connection. The Admin Dashboard requires an active internet connection.';

const String kNoInternetActionMessage =
    'This action requires an internet connection. Please reconnect and try again.';
