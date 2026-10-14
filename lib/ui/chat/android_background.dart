import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/notes.dart';
import 'background_work.dart';

/// [BackgroundWork] over `MainActivity`'s `anywherellm/background` channel: `AnswerService`, a
/// foreground service, holds the app, and `Notes` draws a ready answer. `MainActivity` hands
/// over each notification tapped: `launchTap` answers the one that started the activity, once,
/// and `tap` sends one tapped while it runs.
class AndroidBackground implements BackgroundWork {
  AndroidBackground() {
    _native.setMethodCallHandler((call) async {
      if (call.method == 'tap') _tapped(call.arguments);
    });
    unawaited(_launchTap());
  }

  static const _native = MethodChannel('anywherellm/background');

  final _taps = StreamController<ChatTarget>();

  /// The notification that started the activity, if one did; nothing where the app runs without
  /// `MainActivity`'s channel, as in a test.
  Future<void> _launchTap() async {
    try {
      _tapped(await _native.invokeMethod<Object?>('launchTap'));
    } on MissingPluginException {
      return;
    }
  }

  void _tapped(Object? payload) {
    if (payload is! String) return;
    if (chatTargetOf(payload) case final target?) _taps.add(target);
  }

  @override
  Future<void> hold(String? what) => _native.invokeMethod('hold', what);

  @override
  Future<void> ready({
    required String title,
    required String body,
    required String slug,
    required String thread,
  }) => _native.invokeMethod(
    'ready',
    answerReadyPayload(title: title, body: body, slug: slug, thread: thread),
  );

  @override
  Future<void> leave() => _native.invokeMethod('leave');

  @override
  Stream<ChatTarget> get taps => _taps.stream;
}
