import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Wraps the whole app so it can tell the user when they're offline (still
/// fully usable — Firestore's own on-device cache keeps the app working
/// off cached data) and when they've just come back online (Firestore
/// syncs automatically the moment connectivity returns; this is purely a
/// visible confirmation that a sync is happening).
class ConnectivityBanner extends StatefulWidget {
  final Widget child;
  const ConnectivityBanner({super.key, required this.child});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _offline = false;
  bool _showSyncing = false;
  Timer? _syncingTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final initial = await Connectivity().checkConnectivity();
      _handle(initial);
    } catch (_) {
      // Connectivity plugin unavailable on this platform — assume online
      // rather than showing a false "offline" banner forever.
    }
    _sub = Connectivity().onConnectivityChanged.listen(_handle);
  }

  void _handle(List<ConnectivityResult> results) {
    final isOffline = results.every((r) => r == ConnectivityResult.none);
    if (!mounted || isOffline == _offline) return;

    final wasOffline = _offline;
    setState(() => _offline = isOffline);

    if (wasOffline && !isOffline) {
      // Just came back online — Firestore's local cache syncs on its own;
      // this is just a brief, visible confirmation for the user.
      setState(() => _showSyncing = true);
      _syncingTimer?.cancel();
      _syncingTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showSyncing = false);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _syncingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_offline || _showSyncing)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Material(
                color: _offline ? Colors.red[700] : Colors.green[700],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _offline ? Icons.cloud_off_outlined : Icons.sync_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _offline
                            ? 'No internet connection — showing saved data'
                            : 'Back online — syncing recent activity…',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
