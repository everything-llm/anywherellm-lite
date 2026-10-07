import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../links.dart';
import '../state/chat_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/side_panel.dart';
import 'browser_chip.dart';
import 'card_image.dart';

/// The chat on screen's everythingllm browser, beside the chat: its newest card drawn large and
/// live, Take over to open the browser's take-over view, and the steps of the answer running
/// in it, or else of the last answer that used it. It follows the chat on screen. The card is
/// followed only while it can be seen, since a watched card keeps the server's browser from
/// being stopped.
class BrowserPanel extends StatelessWidget {
  const BrowserPanel({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => BrowserStateBuilder(builder: _build);

  Widget _build(BuildContext context, Turn? running) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final card = scope.chat.browserCard;
    // The running answer comes first, since it is the chat's newest turn.
    final used = scope.chat.turns.reversed
        .where((turn) => turn.browserSteps.isNotEmpty)
        .firstOrNull;
    final settings = scope.settings;
    return SidePanel(
      title: 'Browser',
      about: running?.browsing ?? false
          ? 'The agent is using it: ${running!.status}'
          : card == null
          ? 'The agent has not shown this chat\'s browser yet.'
          : 'The card says who has the browser.',
      live: true,
      onClose: scope.shell.closeBrowser,
      width: width,
      // A Column, not a ListView: a live card is no height until its first frame, and a list
      // drops a child of no height at its start and never builds it again.
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (card != null) ...[
              CardImage(
                card.image,
                key: ValueKey(card.image),
                alt: card.title,
                server: settings.connection?.uri,
                allowHttp: settings.allowHttp,
                linked: true,
                maxHeight: 520,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  'Take over',
                  primary: true,
                  onPressed: () => openLink(context, card.page.toString()),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Opens the browser to watch or use it yourself.',
                style: Type.sans(12.5, color: t.muted),
              ),
            ],
            if (used != null) ...[
              const SizedBox(height: 16),
              Text(
                identical(used, running)
                    ? 'This answer\'s steps'
                    : 'The last answer\'s steps',
                style: Type.sans(13, weight: FontWeight.w600, color: t.ink2),
              ),
              const SizedBox(height: 6),
              BrowserSteps(used.browserSteps, now: used.browsing),
            ],
          ],
        ),
      ),
    );
  }
}
