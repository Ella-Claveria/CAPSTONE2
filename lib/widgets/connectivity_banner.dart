import 'dart:async';

import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';

/// Wraps the whole app so it can warn the user the moment connectivity is
/// lost while they're already inside it. AgriTrade+ requires live Firebase
/// data, so this is a warning, not just an FYI — screens keep whatever they
/// last rendered, but every write action re-checks connectivity itself
/// (see requireOnlineOrError) and refuses to run while offline rather than
/// silently queuing a marketplace transaction for later. Reads its status
/// from the single shared [ConnectivityService] so there's only ever one
/// connectivity watchdog running, not one per widget.
class ConnectivityBanner extends StatefulWidget {
  final Widget child;
  const ConnectivityBanner({super.key, required this.child});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  StreamSubscription<bool>? _sub;
  bool _offline = false;
  bool _showBackOnline = false;
  Timer? _backOnlineTimer;

  @override
  void initState() {
    super.initState();
    final known = ConnectivityService.instance.lastKnownOnline;
    if (known != null) _offline = !known;
    _sub = ConnectivityService.instance.onStatusChanged.listen(_handle);
  }

  void _handle(bool online) {
    if (!mounted) return;
    final wasOffline = _offline;
    setState(() => _offline = !online);

    if (wasOffline && online) {
      // Just came back online — Firestore's live listeners resume on their
      // own; this is just a brief, visible confirmation for the user.
      setState(() => _showBackOnline = true);
      _backOnlineTimer?.cancel();
      _backOnlineTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showBackOnline = false);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _backOnlineTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_offline || _showBackOnline)
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
                      Flexible(
                        child: Text(
                          _offline
                              ? 'No internet connection — some actions are unavailable until you\'re back online.'
                              : 'Back online — refreshing…',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
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
