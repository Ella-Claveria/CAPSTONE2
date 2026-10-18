import 'package:flutter/material.dart';

/// The app's own [ScaffoldMessenger] (placed around every screen in
/// main.dart), so every system message (SnackBar) behaves the same:
///
///  * it shows for [shortDuration] instead of Flutter's 4 seconds — unless
///    it has a button to tap (an action) or sets its own duration;
///  * a new message replaces the one on screen at once, instead of waiting
///    in line behind it (which is what made messages seem late).
class AppScaffoldMessenger extends ScaffoldMessenger {
  const AppScaffoldMessenger({super.key, required super.child});

  static const Duration shortDuration = Duration(seconds: 2);

  @override
  ScaffoldMessengerState createState() => _AppScaffoldMessengerState();
}

class _AppScaffoldMessengerState extends ScaffoldMessengerState {
  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    removeCurrentSnackBar();
    return super.showSnackBar(
      shortenedSnackBar(snackBar),
      snackBarAnimationStyle: snackBarAnimationStyle,
    );
  }
}

/// [snackBar] shown for [AppScaffoldMessenger.shortDuration], when it
/// would otherwise use the default 4 seconds and has no action.
SnackBar shortenedSnackBar(SnackBar snackBar) {
  const flutterDefault = Duration(milliseconds: 4000);
  if (snackBar.action != null || snackBar.duration != flutterDefault) {
    return snackBar;
  }
  return SnackBar(
    key: snackBar.key,
    content: snackBar.content,
    backgroundColor: snackBar.backgroundColor,
    elevation: snackBar.elevation,
    margin: snackBar.margin,
    padding: snackBar.padding,
    width: snackBar.width,
    shape: snackBar.shape,
    hitTestBehavior: snackBar.hitTestBehavior,
    behavior: snackBar.behavior,
    actionOverflowThreshold: snackBar.actionOverflowThreshold,
    showCloseIcon: snackBar.showCloseIcon,
    closeIconColor: snackBar.closeIconColor,
    duration: AppScaffoldMessenger.shortDuration,
    persist: snackBar.persist,
    animation: snackBar.animation,
    onVisible: snackBar.onVisible,
    dismissDirection: snackBar.dismissDirection,
    clipBehavior: snackBar.clipBehavior,
  );
}
