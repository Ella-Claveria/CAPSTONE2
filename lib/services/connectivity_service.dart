import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

/// The three situations the app tells apart.
enum ConnectionStatus {
  /// The internet cannot be reached at all — the only case that shows the
  /// offline banner / No Internet screen.
  noInternet,

  /// The internet works but Firebase did not answer (slow, erroring or
  /// down). Not "offline": no offline UI is shown for this.
  firebaseUnavailable,

  /// Internet and Firebase both answer.
  online,
}

/// AgriTrade+ depends on live Firebase data everywhere — farmer approval
/// status, inventory, orders, admin stats — so this app cannot work
/// meaningfully offline. Three different things are tracked here and never
/// confused with each other:
///
///  * the network link — what connectivity_plus reports (Wi-Fi, mobile,
///    none). It is only a hint and a trigger to re-check: it can say
///    "none" for a moment while the device switches networks, and it can
///    say "wifi" on a captive portal with no real access.
///  * internet reachability — whether a small HTTPS request to a public
///    endpoint gets any answer. This is the main test of "online".
///  * Firebase availability — a forced-server read of `market_prices`
///    (`allow read: if true` in firestore.rules, so it works before
///    sign-in). It is an extra signal only: a Firebase answer proves the
///    internet works, but a Firebase timeout or error never means "no
///    internet" by itself.
///
/// The app is offline only when the HTTPS check AND Firebase both fail.
/// (On web the browser blocks cross-site HTTPS checks, so the Admin portal
/// relies on the Firebase read alone.)
///
/// The app-wide state (what the warning banner shows) only turns offline
/// after a failed check is confirmed by a second one a few seconds later,
/// so one slow or dropped request never raises the banner. While offline
/// the check repeats on a short timer, so the state clears by itself the
/// moment the internet answers again. This is the single source of truth
/// for connectivity across the app: the splash gate, the banner and every
/// guarded write all go through this one instance.
class ConnectivityService with WidgetsBindingObserver {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  static const Duration _httpsTimeout = Duration(seconds: 8);
  static const Duration _firebaseTimeout = Duration(seconds: 10);
  static const Duration _cacheTtl = Duration(seconds: 5);
  // How long a failed check waits before it is confirmed.
  static const Duration _offlineDebounce = Duration(seconds: 5);
  // How often reachability is re-checked while the app is offline.
  static const Duration _offlineRetryInterval = Duration(seconds: 5);

  // Small public "is the internet there" endpoints, run by two different
  // providers so one of them being down or blocked is not read as offline.
  // Asked in parallel; the first answer wins.
  static final List<Uri> _httpsProbeUrls = [
    Uri.parse('https://www.gstatic.com/generate_204'),
    Uri.parse('https://cp.cloudflare.com/generate_204'),
  ];

  // Whether Firebase answered the most recent check; null until one ends.
  bool? _firebaseAvailable;

  // The confirmed app-wide state; null until the first check completes.
  bool? _online;
  // The raw result of the most recent reachability check (not debounced).
  bool? _lastProbe;
  DateTime? _lastCheckedAt;
  // What connectivity_plus last reported; null if it could not be read.
  bool? _hasNetworkLink;
  Future<bool>? _inFlight;
  bool _watching = false;
  StreamSubscription<List<ConnectivityResult>>? _netSub;
  Timer? _confirmTimer;
  Timer? _retryTimer;

  final _statusController = StreamController<bool>.broadcast();

  /// The confirmed online/offline state, or null if no check has completed
  /// yet.
  bool? get lastKnownOnline => _online;

  /// Which of the three situations the app is in, or null if no check has
  /// completed yet.
  ConnectionStatus? get status {
    if (_online == null) return null;
    if (_online == false) return ConnectionStatus.noInternet;
    return _firebaseAvailable == false
        ? ConnectionStatus.firebaseUnavailable
        : ConnectionStatus.online;
  }

  /// Whether connectivity_plus last reported a Wi-Fi/mobile/other link —
  /// the network connection status only, not proof of internet access.
  bool? get hasNetworkLink => _hasNetworkLink;

  /// Fires only on confirmed online/offline transitions while the app is
  /// running — used by the app-wide warning banner (requirement: warn
  /// when connectivity drops mid-session, and let the app recover
  /// automatically once it returns).
  Stream<bool> get onStatusChanged => _statusController.stream;

  static void _log(String message) => debugPrint('[Connectivity] $message');

  /// Starts the background watchdog once per app run. Reachability is
  /// re-checked whenever connectivity_plus reports a change and whenever
  /// the app returns from the background; a connectivity_plus result is
  /// never taken as the answer by itself.
  void startWatching() {
    if (_watching) return;
    _watching = true;
    WidgetsBinding.instance.addObserver(this);
    _netSub = Connectivity().onConnectivityChanged.listen((results) {
      _hasNetworkLink = results.any((r) => r != ConnectivityResult.none);
      _log('connectivity_plus changed → $results');
      checkNow(force: true, reason: 'connectivity changed');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkNow(force: true, reason: 'app resumed');
    }
  }

  /// Not called during normal app life (this is a process-lifetime
  /// singleton) — provided for completeness/tests.
  void dispose() {
    _netSub?.cancel();
    _netSub = null;
    _confirmTimer?.cancel();
    _confirmTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_watching) WidgetsBinding.instance.removeObserver(this);
    _watching = false;
  }

  // Firebase answered: online straight away, with no delay, and any
  // pending "going offline" confirmation is dropped.
  void _markOnline() {
    _confirmTimer?.cancel();
    _confirmTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_online == true) return;
    _log('state → ONLINE (was ${_stateName(_online)})');
    _online = true;
    _statusController.add(true);
  }

  void _markOffline(String reason) {
    if (_online == false) return;
    _log(
      'state → OFFLINE (was ${_stateName(_online)}) — banner shown because: '
      '$reason',
    );
    _online = false;
    _statusController.add(false);
    // Keep checking until Firebase answers, so the offline state can never
    // outlive the outage.
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(_offlineRetryInterval, (_) async {
      if (await _probe('offline retry') == null) _markOnline();
    });
  }

  static String _stateName(bool? online) =>
      online == null ? 'unknown' : (online ? 'online' : 'offline');

  // A check failed while the app was not already offline: wait, then check
  // once more before telling the app it is offline.
  void _confirmOffline(String failure) {
    if (_online == false || _confirmTimer != null) return;
    _log(
      'reachability check failed ($failure) — re-checking in '
      '${_offlineDebounce.inSeconds}s before going offline',
    );
    late final Timer timer;
    timer = Timer(_offlineDebounce, () async {
      final secondFailure = await _probe('offline confirmation');
      // Another check answered in the meantime and cancelled this one.
      if (!identical(_confirmTimer, timer)) return;
      _confirmTimer = null;
      if (secondFailure == null) {
        _markOnline();
      } else {
        _markOffline(
          'two reachability checks in a row failed ($secondFailure; '
          'network link: ${_linkName()})',
        );
      }
    });
    _confirmTimer = timer;
  }

  String _linkName() => _hasNetworkLink == null
      ? 'unknown'
      : (_hasNetworkLink! ? 'connected' : 'none');

  /// Confirms real reachability right now and returns the result of this
  /// one check. A short cache avoids re-probing Firebase for calls made
  /// within a couple of seconds of each other (e.g. several guarded
  /// actions in a row); pass `force: true` to bypass it — the splash
  /// screen's Retry button always forces a fresh check. [reason] only
  /// labels the debug log.
  Future<bool> checkNow({bool force = false, String reason = 'check'}) {
    if (!force && _lastProbe != null && _lastCheckedAt != null) {
      if (DateTime.now().difference(_lastCheckedAt!) < _cacheTtl) {
        return Future.value(_lastProbe);
      }
    }
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = _check(reason);
    _inFlight = future;
    future.whenComplete(() => _inFlight = null);
    return future;
  }

  Future<bool> _check(String reason) async {
    final failure = await _probe(reason);
    if (failure == null) {
      _markOnline();
      return true;
    }
    _confirmOffline(failure);
    return false;
  }

  // One full check. Returns null when the internet is reachable, or a
  // short description of why it is not. The internet counts as reachable
  // when the HTTPS check answers OR Firebase answers; a Firebase failure
  // while HTTPS works is recorded (see [status]) but is not "offline".
  Future<String?> _probe(String reason) async {
    try {
      final netResults = await Connectivity().checkConnectivity();
      _hasNetworkLink = netResults.any((r) => r != ConnectivityResult.none);
      _log('[$reason] connectivity type → $netResults');
    } catch (e) {
      // connectivity_plus unavailable on this platform/build. It is only a
      // hint; the checks below decide.
      _hasNetworkLink = null;
      _log('[$reason] connectivity type unavailable ($e)');
    }

    // Both run at once; Firebase is only waited for when HTTPS fails.
    final firebaseCheck = _firebaseFailure();
    void recordFirebase(String? firebaseFailure) {
      _firebaseAvailable = firebaseFailure == null;
      _log(
        '[$reason] Firebase → '
        '${firebaseFailure == null ? 'AVAILABLE' : 'UNAVAILABLE ($firebaseFailure)'}',
      );
    }

    String? failure;
    if (kIsWeb) {
      final firebaseFailure = await firebaseCheck;
      recordFirebase(firebaseFailure);
      failure = firebaseFailure;
    } else {
      final httpsFailure = await _httpsFailure();
      _log(
        '[$reason] HTTPS reachability → '
        '${httpsFailure == null ? 'REACHABLE' : 'UNREACHABLE ($httpsFailure)'}',
      );
      if (httpsFailure == null) {
        // Online already; Firebase's answer only updates [status].
        unawaited(firebaseCheck.then(recordFirebase));
      } else {
        final firebaseFailure = await firebaseCheck;
        recordFirebase(firebaseFailure);
        if (firebaseFailure != null) {
          failure = 'HTTPS: $httpsFailure; Firebase: $firebaseFailure';
        }
      }
    }

    _lastProbe = failure == null;
    _lastCheckedAt = DateTime.now();
    _log(
      '[$reason] decision → '
      '${failure == null ? 'ONLINE (internet reachable)' : 'NO INTERNET ($failure)'}',
    );
    return failure;
  }

  // The main internet test: null as soon as any endpoint answers (any
  // HTTP status counts — over HTTPS only the real server can answer), or
  // a description once every endpoint has failed.
  Future<String?> _httpsFailure() {
    final result = Completer<String?>();
    var pending = _httpsProbeUrls.length;
    for (final url in _httpsProbeUrls) {
      http
          .head(url)
          .timeout(_httpsTimeout)
          .then<Object?>((_) => null, onError: (Object e) => e)
          .then((error) {
            pending--;
            if (result.isCompleted) return;
            if (error == null) {
              result.complete(null);
            } else if (pending == 0) {
              result.complete(
                error is TimeoutException
                    ? 'no answer in ${_httpsTimeout.inSeconds}s'
                    : 'request failed (${error.runtimeType})',
              );
            }
          });
    }
    return result.future;
  }

  // The extra signal: null when Firebase answered, or why it did not.
  Future<String?> _firebaseFailure() async {
    try {
      await FirebaseFirestore.instance
          .collection('market_prices')
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(_firebaseTimeout);
      return null;
    } on TimeoutException {
      return 'no answer in ${_firebaseTimeout.inSeconds}s';
    } on FirebaseException catch (e) {
      // Only these codes mean the request never got through. Any other
      // error (permission-denied, unauthenticated...) is an answer from
      // the server.
      const unreachable = {'unavailable', 'deadline-exceeded', 'unknown'};
      return unreachable.contains(e.code) ? 'error ${e.code}' : null;
    } catch (e) {
      return 'request failed ($e)';
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

const String kNoInternetMessage =
    'AgriTrade+ needs an internet connection to load the latest marketplace '
    'information, messages, and orders.';

const String kNoInternetAdminMessage =
    'No internet connection. The Admin Dashboard requires an active internet connection.';

const String kNoInternetActionMessage =
    'This action requires an internet connection. Please reconnect and try again.';
