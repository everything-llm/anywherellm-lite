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
/// controls. A comment the page posts to [appsChannel] is sent in the chat under the sheet, as
/// the person's message, and the sheet closes so its answer shows. Esc, Back on the device, the
/// scrim and a drag down close it, and so does the page's own `window.close()`.
class PageSheet extends StatefulWidget {
  const PageSheet(this.page, {super.key});

  final Uri page;

  @override
  State<PageSheet> createState() => _PageSheetState();
}

class _PageSheetState extends State<PageSheet> {
  late final _channel = PageChannel(appsChannel, _heard);

  /// Sends the comment [message] holds in the chat on screen, and tells the page whether it
  /// went: a comment on an app of another workspace, or one the chat cannot take now, does not.
  Future<void> _heard(String message) async {
    final comment = pageCommentOf(jsonOrNull(message));
    if (comment == null) return;
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final problem = comment.workspace != chat.activeSlug
        ? 'This app is in another workspace: open a chat there to comment on it.'
        : await chat.send(comment.message)
        ? null
        : 'The chat can’t take a message now: try again once it’s free.';
    final said = jsonEncode({'ok': problem == null, 'why': ?problem});
    await _channel.run(
      'window.dispatchEvent(new CustomEvent("anywherellm-comment",{detail:$said}))',
    );
    if (problem == null && mounted) scope.shell.closePage();
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
          : view.show(
              widget.page,
              onLeave: (url) => openLink(context, url.toString()),
              onClose: scope.shell.closePage,
              channel: _channel,
            ),
    );
  }
}
