import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../core/apps_lean.dart';
import '../../core/json.dart';
import '../app_scope.dart';
import '../apps/app_view.dart';
import '../links.dart';
import '../widgets/sheet.dart';

/// The channel an apps-lean page posts its Comment to; seeing it, the page offers Comment.
const appsChannel = 'AnywhereLLMApps';

/// A page on the connected server that an answer links to, such as an apps-lean app's page, in
/// a tall sheet over the chat: the page edge to edge under the drag handle, drawing its own
/// controls. A comment the page posts to [appsChannel] asks Send this to the chat? over the page,
/// and once sent goes in the chat under the sheet as the person's message, and the sheet closes
/// so its answer shows. Esc, Back on the device, the
/// scrim and a drag down close it, and so does the page's own `window.close()`.
class PageSheet extends StatefulWidget {
  const PageSheet(this.page, {super.key});

  final Uri page;

  @override
  State<PageSheet> createState() => _PageSheetState();
}

class _PageSheetState extends State<PageSheet> {
  late final _channel = PageChannel(appsChannel, _heard);

  /// The comment the page posted, waiting for the person to send it or not.
  PageComment? _pending;

  /// Holds the comment [message] holds for the person to send, telling the page when it will
  /// not go: a comment on an app of another workspace, or one posted while another waits.
  Future<void> _heard(String message) async {
    final comment = pageCommentOf(jsonOrNull(message));
    if (comment == null) return;
    if (comment.workspace != AppScope.of(context).chat.activeSlug) {
      return _answer(
        'This app is in another workspace: open a chat there to comment on it.',
      );
    }
    if (_pending != null) return _answer('Another comment is waiting.');
    setState(() => _pending = comment);
  }

  /// Sends the waiting comment in the chat on screen, and tells the page whether it went.
  Future<void> _send() async {
    final comment = _pending;
    if (comment == null) return;
    setState(() => _pending = null);
    final scope = AppScope.of(context);
    final sent = await scope.chat.send(comment.message);
    await _answer(
      sent
          ? null
          : 'The chat can’t take a message now: try again once it’s free.',
    );
    if (sent && mounted) scope.shell.closePage();
  }

  /// Lets go of the waiting comment unsent.
  void _cancel() {
    setState(() => _pending = null);
    unawaited(_answer('Not sent.'));
  }

  /// Tells the page whether its comment went: it did when [problem] is null.
  Future<void> _answer(String? problem) {
    final said = jsonEncode({'ok': problem == null, 'why': ?problem});
    return _channel.run(
      'window.dispatchEvent(new CustomEvent("anywherellm-comment",{detail:$said}))',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final view = scope.appView;
    return SheetFrame(
      title: 'The app’s page',
      bare: true,
      height: SheetHeight.tall,
      padding: EdgeInsets.zero,
      onClose: scope.shell.closePage,
      child: view == null
          ? const SizedBox.shrink()
          // A page can post a comment without the person, so it waits for them over the page,
          // which stays as it was. Cancel and the scrim let go of it; Esc and Back close the
          // page, as they close a sheet whose question shows, and it goes unsent.
          : PopupSheet(
              open: _pending != null,
              onClose: _cancel,
              title: 'Send this to the chat?',
              sheet: (context) => SheetQuestion(
                _pending?.message ?? '',
                keep: 'Cancel',
                action: 'Send',
                danger: false,
                onKeep: _cancel,
                onConfirm: _send,
              ),
              child: view.show(
                widget.page,
                onLeave: (url) => openLink(context, url.toString()),
                onClose: scope.shell.closePage,
                channel: _channel,
              ),
            ),
    );
  }
}
