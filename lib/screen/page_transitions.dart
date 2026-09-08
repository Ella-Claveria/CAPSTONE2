import 'package:flutter/material.dart';

/// Standard "moving forward through a process" transition: pushing a page
/// slides it in from the right (replacing the platform default), and
/// popping it back off automatically reverses that same animation, sliding
/// it back out to the right — so the direction always matches whether
/// you're going deeper into a flow or backing out of it.
PageRouteBuilder slideRoute(Widget page, {Duration duration = const Duration(milliseconds: 300)}) {
  return PageRouteBuilder(
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final tween = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeInOutCubic));
      return SlideTransition(position: animation.drive(tween), child: child);
    },
  );
}

PageRouteBuilder fadeSlideRoute(Widget page, {Duration duration = const Duration(milliseconds: 550)}) {
  return PageRouteBuilder(
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);

      final fade = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.06), // subtle upward drift, not a full slide
        end: Offset.zero,
      ).animate(curved);

      return FadeTransition(
        opacity: fade,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}