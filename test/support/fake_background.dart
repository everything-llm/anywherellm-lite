import 'dart:async';

import 'package:anywherellm/ui/chat/background_work.dart';

/// What keeps answers going, kept in memory: [held] is what each hold said, null for a release,
/// [readied] each ready answer as `<title>: <body> @ <slug>/<thread>`, [asks] each request shown
/// the same way, null for one taken back, and [left] how many times the app was put out of
/// sight; [tap] acts as a tapped notification.
class FakeBackground implements BackgroundWork {
  final held = <String?>[];
  final readied = <String>[];
  final asks = <String?>[];
  var left = 0;
  final _taps = StreamController<ChatTarget>();

  void tap(ChatTarget target) => _taps.add(target);

  @override
  Future<void> hold(String? what) async => held.add(what);

  @override
  Future<void> ready({
    required String title,
    required String body,
    required String slug,
    required String thread,
  }) async => readied.add('$title: $body @ $slug/$thread');

  @override
  Future<void> asking({
    required String title,
    required String body,
    required String slug,
    required String thread,
  }) async => asks.add('$title: $body @ $slug/$thread');

  @override
  Future<void> asked() async => asks.add(null);

  @override
  Future<void> leave() async => left++;

  @override
  Stream<ChatTarget> get taps => _taps.stream;
}
