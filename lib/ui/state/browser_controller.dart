import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/browser.dart';
import '../../core/ports.dart';
import 'chat_controller.dart';
import 'notice.dart';
import 'shell_controller.dart';

/// The everythingllm browser of the chat on screen as the server says it. It reads when a chat
/// comes on screen, to learn whether the chat has a tab; each time the status of the answer
/// running in it changes, so the card shows from the agent's first step; when that answer ends;
/// and every [every] while the Browser panel is open. A server that does not say leaves
/// [browser] null, and the chat's browser is then only what its answers show.
class BrowserController extends ChangeNotifier {
  BrowserController(
    this._api,
    this._chat,
    this._shell, {
    this.every = const Duration(seconds: 2),
  }) {
    _chat.addListener(_changed);
    _shell.addListener(_changed);
    _changed();
  }

  final AnythingLlmApi _api;
  final ChatController _chat;
  final ShellController _shell;

  /// How often the browser is read while its panel is open, or null never.
  final Duration? every;

  /// What the server says of the chat on screen's browser, or null before it says, or when it
  /// does not.
  ChatBrowser? browser;

  /// Why the browser could not be handed back.
  Notice? problem;

  /// Whether the browser is being handed back to the agent.
  bool handing = false;

  /// The chat [browser] describes.
  ({String slug, String thread})? _of;

  Timer? _timer;
  bool _reading = false;

  /// The answer whose status changes are read.
  Turn? _watching;

  /// Whether the take-over view is on screen. It follows the browser itself, so the browser is
  /// not read meanwhile, and is read once as it closes.
  bool get viewShown => _viewShown;
  bool _viewShown = false;
  set viewShown(bool shown) {
    if (shown == _viewShown) return;
    _viewShown = shown;
    if (!shown) unawaited(read());
    _changed();
  }

  /// The tab of the chat on screen, or null when it has none.
  BrowserTab? get tab => browser?.tab;

  /// The newest login request waiting for the person, or null.
  BrowserLogin? get waitingLogin => browser?.waitingLogin;

  ({String slug, String thread})? get _here {
    final slug = _chat.activeSlug;
    final thread = _chat.activeThread;
    return slug == null || thread == null ? null : (slug: slug, thread: thread);
  }

  void _changed() {
    final here = _here;
    if (here != _of) {
      _of = here;
      browser = null;
      problem = null;
      handing = false;
      notifyListeners();
      if (here != null) unawaited(read());
    }
    final running = _chat.runningHere;
    if (!identical(running, _watching)) {
      _watching?.statusChanges.removeListener(_status);
      _watching = running;
      running?.statusChanges.addListener(_status);
      // An answer that ends is the last word on what the browser did.
      if (running == null && here != null) unawaited(read());
    }
    final period = every;
    final wanted =
        here != null && period != null && _shell.browserOpen && !_viewShown;
    if (wanted && _timer == null) {
      _timer = Timer.periodic(period, (_) => unawaited(read()));
    } else if (!wanted) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _status() => unawaited(read());

  /// Reads the browser of the chat on screen again.
  Future<void> read() async {
    final here = _of;
    if (here == null || _reading) return;
    _reading = true;
    try {
      final read = await _api.chatBrowser(here.slug, here.thread);
      if (_of != here || (read == null && browser == null)) return;
      browser = read;
      notifyListeners();
    } finally {
      _reading = false;
    }
  }

  /// The tab as one picture, or null when there is none or it cannot be read. [etag] is the
  /// last picture's, and an unchanged picture has no bytes.
  Future<({Uint8List? bytes, String? etag})?> frame({
    String? etag,
    bool light = false,
  }) async {
    final here = _of;
    if (here == null) return null;
    try {
      return await _api.browserFrame(
        here.slug,
        here.thread,
        etag: etag,
        light: light,
      );
    } on ApiException {
      return null;
    }
  }

  /// Gives the browser back to the agent, which the person has taken over.
  Future<void> handBack() async {
    final here = _of;
    if (here == null || handing) return;
    handing = true;
    problem = null;
    notifyListeners();
    try {
      final answered = await _api.handBackBrowser(here.slug, here.thread);
      if (_of == here) browser = answered;
    } on ApiException catch (error) {
      if (_of == here) {
        problem = Notice('Could not hand the browser back', error.message);
      }
    }
    if (_of == here) {
      handing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _watching?.statusChanges.removeListener(_status);
    _chat.removeListener(_changed);
    _shell.removeListener(_changed);
    super.dispose();
  }
}
