import 'package:flutter/services.dart';

import '../../core/push.dart';
import 'background_work.dart';

/// [BackgroundWork] over `MainActivity`'s `anywherellm/background` channel: `AnswerService`, a
/// foreground service, holds the app, and `PushNotes` draws a ready answer on the
/// [answersChannel].
class AndroidBackground implements BackgroundWork {
  const AndroidBackground();

  static const _native = MethodChannel('anywherellm/background');

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
}
