import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

// On the web: plain HTML elements turned by CSS animations (see
// busy_indicator.dart). The browser runs a transform animation on its own
// compositor, so it keeps moving while Dart is busy building a file.

bool _styleAdded = false;

void _addStyle() {
  if (_styleAdded) return;
  _styleAdded = true;
  final style = web.document.createElement('style') as web.HTMLStyleElement;
  style.textContent = '''
@keyframes agri-busy-spin { to { transform: rotate(360deg); } }
@keyframes agri-busy-slide {
  from { transform: translateX(-100%); }
  to { transform: translateX(260%); }
}
''';
  web.document.head?.append(style);
}

String _css(Color color) =>
    'rgba(${(color.r * 255).round()}, ${(color.g * 255).round()}, '
    '${(color.b * 255).round()}, ${color.a.toStringAsFixed(3)})';

Widget busySpinner({required Color color, required double strokeWidth}) {
  _addStyle();
  return HtmlElementView.fromTagName(
    tagName: 'div',
    isVisible: true,
    onElementCreated: (element) {
      final box = element as web.HTMLElement;
      box.style
        ..width = '100%'
        ..height = '100%'
        ..pointerEvents = 'none';
      final ring = web.document.createElement('div') as web.HTMLElement;
      ring.style
        ..boxSizing = 'border-box'
        ..width = '100%'
        ..height = '100%'
        ..borderRadius = '50%'
        ..border =
            '${strokeWidth}px solid ${_css(color.withValues(alpha: 0.2))}'
        ..borderTopColor = _css(color)
        ..borderRightColor = _css(color)
        ..setProperty('will-change', 'transform')
        ..animation = 'agri-busy-spin 0.8s linear infinite';
      box.append(ring);
    },
  );
}

Widget busyBar({required Color color, required Color trackColor}) {
  _addStyle();
  return HtmlElementView.fromTagName(
    tagName: 'div',
    isVisible: true,
    onElementCreated: (element) {
      final track = element as web.HTMLElement;
      track.style
        ..width = '100%'
        ..height = '100%'
        ..overflow = 'hidden'
        ..borderRadius = '999px'
        ..background = _css(trackColor)
        ..pointerEvents = 'none';
      final stripe = web.document.createElement('div') as web.HTMLElement;
      stripe.style
        ..width = '40%'
        ..height = '100%'
        ..borderRadius = '999px'
        ..background = _css(color)
        ..setProperty('will-change', 'transform')
        ..animation = 'agri-busy-slide 1.2s ease-in-out infinite';
      track.append(stripe);
    },
  );
}
