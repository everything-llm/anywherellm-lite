import 'package:anywherellm/ui/chat/background_work.dart';

/// What keeps answers going, kept in memory: [held] is what each hold said, null for a release,
/// [readied] each ready answer as `<title>: <body> @ <slug>/<thread>`, and [left] how many times
/// the app was put out of sight.
class FakeBackground implements BackgroundWork {
  final held = <String?>[];
  final readied = <String>[];
  var left = 0;

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
  Future<void> leave() async => left++;
}
