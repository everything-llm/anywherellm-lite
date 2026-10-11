import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../links.dart';
import '../state/chat_controller.dart';
import '../tokens.dart';
import '../type.dart';
import 'app_panel.dart';
import 'composer.dart';

/// The chat's browser on a phone that has a web view: everythingllm's take-over view, full
/// screen, in the app's theme. The view draws the screen itself: Back, who has the tab beside
/// its address, which a tap edits, Saved logins, the page, which a touch takes, the requests
/// that wait, and the message bar, whose messages go into the chat ([sayInChat]).
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, required this.view, required this.page});

  final TakeoverView view;
  final Uri page;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  /// The address first shown: the server's word on the tab can come after a card's link
  /// opened it, and another address would load the view again.
  Uri? _page;

  late final _browser = AppScope.of(context).browser;

  // The view follows the browser itself meanwhile.
  @override
  void initState() {
    super.initState();
    _browser.viewShown = true;
  }

  @override
  void dispose() {
    _browser.viewShown = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final page = _page ??= themedFor(context, widget.page);
    return ColoredBox(
      color: t.bg,
      child: widget.view.show(
        page,
        placeholder: Center(
          child: Text(
            'Opening the browser…',
            style: Type.sans(15, color: t.muted),
          ),
        ),
        onBack: scope.shell.closeBrowser,
        onSay: (text) => sayInChat(scope.chat, text),
        onLeave: (url) => openLink(context, url.toString()),
      ),
    );
  }
}

/// Sends [text] from the browser's message bar into the chat on screen; while the chat answers,
/// holds it in the composer to go when the answer ends, as Send when done does; and while
/// another chat's answer holds the workspace, leaves it in the composer. Says how it went, for
/// the bar to show.
Future<String> sayInChat(ChatController chat, String text) async {
  if (canSend(chat, text) && await chat.send(text)) return 'Sent: $text';
  final hold = chat.runningHere != null;
  chat.putInComposer(text, const [], hold: hold);
  return hold
      ? 'Sends when this answer ends: $text'
      : 'In the chat\'s message box: $text';
}
