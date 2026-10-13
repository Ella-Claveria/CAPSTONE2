import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Listens for a laptop trackpad's two-finger scroll, before the page (or
/// an embedded Google Map, which would zoom on it) sees it.
///
/// [onScroll] gets the pointer's position and the scroll distance in
/// logical pixels, and returns whether it used the scroll — only then is
/// the event kept from everything else. A mouse wheel and a pinch are
/// never passed on, so both still zoom the map.
///
/// Returns the function that stops listening.
void Function() listenTrackpadPan(
  bool Function(double x, double y, double dx, double dy) onScroll,
) {
  // A trackpad swipe is a run of small scrolls; once one is recognized,
  // the rest of the run (and its glide) is the same swipe.
  var lastTrackpadScroll = 0.0;

  bool isTrackpad(web.WheelEvent event) {
    final now = event.timeStamp.toDouble();
    if (now - lastTrackpadScroll < 400) return true;
    // Scrolling by lines or pages is a mouse wheel.
    if (event.deltaMode != 0) return false;
    if (event.deltaX != 0) return true;
    // A mouse wheel turns in whole notches of 120.
    final notch = event.getProperty<JSAny?>('wheelDeltaY'.toJS);
    final wheelDelta = notch.isA<JSNumber>()
        ? (notch! as JSNumber).toDartDouble.abs()
        : 0.0;
    return wheelDelta == 0 || wheelDelta % 120 != 0;
  }

  void handle(web.WheelEvent event) {
    // A pinch arrives as a scroll with Ctrl held: that is a zoom.
    if (event.ctrlKey || event.metaKey) return;
    if (!isTrackpad(event)) return;
    final used = onScroll(
      event.clientX.toDouble(),
      event.clientY.toDouble(),
      event.deltaX.toDouble(),
      event.deltaY.toDouble(),
    );
    if (!used) return;
    lastTrackpadScroll = event.timeStamp.toDouble();
    event.preventDefault();
    event.stopPropagation();
  }

  final listener = handle.toJS;
  web.window.addEventListener(
    'wheel',
    listener,
    web.AddEventListenerOptions(capture: true, passive: false),
  );
  return () => web.window.removeEventListener(
    'wheel',
    listener,
    web.EventListenerOptions(capture: true),
  );
}
