/// Off the web there is no browser wheel event to listen to — the map's
/// own gestures already handle panning there.
void Function() listenTrackpadPan(
  bool Function(double x, double y, double dx, double dy) onScroll,
) => () {};
