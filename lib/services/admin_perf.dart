import 'dart:async';

import 'package:flutter/foundation.dart';

/// Timing logs for the Admin Portal's Firestore work, all under one
/// `[AdminPerf]` tag so a slow query is easy to find in the console:
///
///     [AdminPerf] orders (completed + all): 412 ms — 26 docs
///     [AdminPerf] SLOW users stream, first snapshot: 2310 ms — 11 docs
///
/// Debug output only (debugPrint): nothing is collected or sent anywhere.
class AdminPerf {
  AdminPerf._();

  /// Anything slower than this is tagged SLOW.
  static const Duration slow = Duration(milliseconds: 1000);

  static void _log(String label, Stopwatch watch, String? detail) {
    final ms = watch.elapsedMilliseconds;
    debugPrint(
      '[AdminPerf] ${ms >= slow.inMilliseconds ? 'SLOW ' : ''}$label: $ms ms'
      '${detail == null ? '' : ' — $detail'}',
    );
  }

  /// Runs [run] and logs how long it took. [describe] adds what came back
  /// (e.g. a document count). A failure is logged and rethrown unchanged.
  static Future<T> time<T>(
    String label,
    Future<T> Function() run, {
    String Function(T result)? describe,
  }) async {
    final watch = Stopwatch()..start();
    try {
      final result = await run();
      _log(label, watch, describe?.call(result));
      return result;
    } catch (error) {
      _log(label, watch, 'FAILED: $error');
      rethrow;
    }
  }

  /// [stream], with the time to its first event logged once per listener.
  /// Later events are passed through untouched and unlogged.
  static Stream<T> firstEvent<T>(
    String label,
    Stream<T> stream, {
    String Function(T event)? describe,
  }) {
    final watch = Stopwatch()..start();
    var logged = false;
    return stream.transform(
      StreamTransformer<T, T>.fromHandlers(
        handleData: (event, sink) {
          if (!logged) {
            logged = true;
            _log('$label, first snapshot', watch, describe?.call(event));
          }
          sink.add(event);
        },
        handleError: (error, stack, sink) {
          if (!logged) {
            logged = true;
            _log('$label, first snapshot', watch, 'FAILED: $error');
          }
          sink.addError(error, stack);
        },
      ),
    );
  }
}
