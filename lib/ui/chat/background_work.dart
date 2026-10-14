import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/chat.dart';
import '../../core/markdown.dart';
import '../../core/notes.dart';
import '../state/chat_controller.dart';
import '../state/shell_controller.dart';

/// What lets an answer go on while the app is out of sight: Android keeps an app that holds a
/// foreground service, with its ongoing notification, running and connected.
abstract interface class BackgroundWork {
  /// Keeps the app running with an ongoing notification that says [what], or lets it go when
  /// [what] is null.
  Future<void> hold(String? what);

  /// Shows that the answer in chat [thread] of workspace [slug] is ready, as a notification that
  /// opens the chat, titled [title] over [body].
  Future<void> ready({
    required String title,
    required String body,
    required String slug,
    required String thread,
  });

  /// Puts the app out of sight without ending it, as Back does on its first screen, so an
  /// answer it holds goes on.
  Future<void> leave();

  /// The chat each notification tapped opens, the one that started the app first; buffered until
  /// listened to.
  Stream<ChatTarget> get taps;
}

/// Holds the app in the background while an answer runs or is waited for, and says so when one
/// becomes ready while the app is out of sight. Each time the app comes back to the front, the
/// answers waited for are read for again. A tapped notification opens its chat.
class KeepAnswering {
  KeepAnswering(this._work, this._chat, this._shell) : _seen = _chat.finished {
    _chat.addListener(_follow);
    _tapsSeen = _work.taps.listen(_open);
    _life = AppLifecycleListener(
      onStateChange: (state) => _front = state == AppLifecycleState.resumed,
      onResume: () => unawaited(_chat.checkWaiting()),
    );
    _follow();
  }

  final BackgroundWork _work;
  final ChatController _chat;
  final ShellController _shell;
  late final AppLifecycleListener _life;
  late final StreamSubscription<ChatTarget> _tapsSeen;

  /// The finished answer last seen, so each is announced once.
  Turn? _seen;

  /// What the ongoing notification says, or null while none shows.
  String? _held;

  /// Whether the app is on screen. Before Android says, it is, as at start.
  bool _front = true;

  void _follow() {
    final slug = _chat.workingIn;
    final want = _chat.working
        ? 'Answering in ${_workspaceName(slug) ?? 'AnythingLLM'}'
        : null;
    if (want != _held) {
      _held = want;
      unawaited(_work.hold(want));
    }
    final finished = _chat.finished;
    if (identical(finished, _seen)) return;
    _seen = finished;
    final where = _chat.finishedIn;
    if (_front || finished == null || where == null) return;
    final chat = _chat
        .threadsOf(where.slug)
        .where((t) => t.slug == where.thread);
    final answer = plainText(splitReasoning(finished.text).answer);
    unawaited(
      _work.ready(
        title: chat.firstOrNull?.name ?? 'Answer ready',
        body: clip(answer, 200),
        slug: where.slug,
        thread: where.thread,
      ),
    );
  }

  String? _workspaceName(String? slug) =>
      _chat.workspaces.where((w) => w.slug == slug).firstOrNull?.name;

  void _open(ChatTarget target) {
    _shell.showTab(HomeTab.chats);
    unawaited(_chat.select(target.slug, thread: target.thread));
    _shell.openChat();
  }

  void dispose() {
    unawaited(_tapsSeen.cancel());
    _chat.removeListener(_follow);
    _life.dispose();
    unawaited(_work.hold(null));
  }
}
