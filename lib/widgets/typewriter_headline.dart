import 'dart:async';

import 'package:flutter/material.dart';

/// The login hero's headline, typed out one character at a time with a
/// blinking cursor; once it is complete, a short pause, then the subtitle
/// fades in. The finished headline stays on screen.
///
/// The whole headline is laid out from the start — the part not typed yet
/// is drawn transparent — so its lines wrap once and never jump while it
/// types. The cursor takes no width for the same reason.
///
/// One AnimationController types, one blinks the cursor, and the pause is
/// a Timer; all of them stop when the widget is disposed. With the system's
/// "remove animations" setting on, the text simply appears complete.
class TypewriterHeadline extends StatefulWidget {
  /// The headline, with [highlight] (a part of it) in [highlightColor].
  final String text;
  final String? highlight;
  final String? subtitle;
  final double fontSize;
  final Color color;
  final Color highlightColor;

  /// Behind [highlight], when set: a band of colour like a marker's.
  final Color? highlightBackground;

  /// Time per character.
  final Duration charDelay;

  /// Before the first character, so the screen settles first.
  final Duration startDelay;

  /// Between the last character and the subtitle.
  final Duration subtitlePause;

  final List<Shadow>? shadows;

  const TypewriterHeadline({
    super.key,
    required this.text,
    this.highlight,
    this.subtitle,
    this.fontSize = 24,
    this.color = Colors.white,
    this.highlightColor = const Color(0xFFB9E58C),
    this.highlightBackground,
    this.charDelay = const Duration(milliseconds: 60),
    this.startDelay = const Duration(milliseconds: 450),
    this.subtitlePause = const Duration(milliseconds: 500),
    this.shadows,
  });

  @override
  State<TypewriterHeadline> createState() => TypewriterHeadlineState();
}

@visibleForTesting
class TypewriterHeadlineState extends State<TypewriterHeadline>
    with TickerProviderStateMixin {
  late final AnimationController _typing = AnimationController(
    vsync: this,
    duration: widget.charDelay * widget.text.length,
  )..addStatusListener(_onTypingStatus);

  late final AnimationController _cursor = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 530),
  );

  Timer? _timer;
  bool _subtitleShown = false;
  bool _cursorShown = true;
  bool _started = false;

  /// How many characters of the headline are showing.
  @visibleForTesting
  int get typedLength => (_typing.value * widget.text.length).floor();

  @visibleForTesting
  bool get subtitleShown => _subtitleShown;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      // No motion wanted: everything at once, no cursor.
      _typing.value = 1;
      _subtitleShown = true;
      _cursorShown = false;
      return;
    }
    _cursor.repeat(reverse: true);
    _timer = Timer(widget.startDelay, () {
      if (mounted) _typing.forward();
    });
  }

  void _onTypingStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _timer?.cancel();
    _timer = Timer(widget.subtitlePause, () {
      if (!mounted) return;
      _cursor.stop();
      setState(() {
        _subtitleShown = true;
        _cursorShown = false;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _typing.dispose();
    _cursor.dispose();
    super.dispose();
  }

  TextStyle get _style => TextStyle(
    fontSize: widget.fontSize,
    // The bundled Montserrat (pubspec.yaml), which has the real bold.
    fontFamily: 'Montserrat',
    fontWeight: FontWeight.w800,
    height: 1.2,
    color: widget.color,
    shadows: widget.shadows,
  );

  // The headline's spans: the typed part in its colours, the cursor, then
  // the rest of the text, transparent and without shadows.
  List<InlineSpan> _spans(int typed) {
    final text = widget.text;
    final start = widget.highlight == null
        ? -1
        : text.indexOf(widget.highlight!);
    final end = start < 0 ? -1 : start + widget.highlight!.length;
    final hidden = _style.copyWith(color: Colors.transparent, shadows: []);

    final spans = <InlineSpan>[];
    void add(int from, int to, TextStyle style) {
      if (to > from) {
        spans.add(TextSpan(text: text.substring(from, to), style: style));
      }
    }

    void addTyped(int from, int to) {
      if (start < 0) return add(from, to, _style);
      // With a [highlightBackground] (a dark colour on the photo), the
      // words sit on a marker-style band so they can still be read.
      final highlighted = _style.copyWith(
        color: widget.highlightColor,
        shadows: widget.highlightBackground == null ? null : const [],
        background: widget.highlightBackground == null
            ? null
            : (Paint()..color = widget.highlightBackground!),
      );
      add(from, to < start ? to : start, _style);
      add(from > start ? from : start, to < end ? to : end, highlighted);
      add(from > end ? from : end, to, _style);
    }

    addTyped(0, typed);
    if (_cursorShown) spans.add(_cursorSpan());
    add(typed, text.length, hidden);
    return spans;
  }

  // A thin bar that takes no width, so the text around it never moves.
  WidgetSpan _cursorSpan() => WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: SizedBox(
      width: 0,
      height: widget.fontSize * 1.05,
      child: OverflowBox(
        maxWidth: 6,
        alignment: Alignment.centerLeft,
        child: FadeTransition(
          opacity: _cursor,
          child: Container(
            margin: const EdgeInsets.only(left: 2),
            width: 2.5,
            color: widget.color,
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: [widget.text, ?widget.subtitle].join('. '),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: _typing,
            builder: (context, _) =>
                Text.rich(TextSpan(children: _spans(typedLength))),
          ),
          if (widget.subtitle != null) ...[
            SizedBox(height: widget.fontSize * 0.35),
            AnimatedOpacity(
              opacity: _subtitleShown ? 1 : 0,
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOut,
              child: AnimatedSlide(
                offset: _subtitleShown ? Offset.zero : const Offset(0, 0.3),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOut,
                child: Text(
                  widget.subtitle!,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: widget.fontSize * 0.56,
                    fontWeight: FontWeight.w500,
                    color: widget.color.withValues(alpha: 0.9),
                    shadows: widget.shadows,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
