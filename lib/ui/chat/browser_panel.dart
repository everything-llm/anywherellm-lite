import 'package:flutter/material.dart';

import '../../core/browser.dart';
import '../app_scope.dart';
import '../links.dart';
import '../state/browser_controller.dart';
import '../state/chat_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/side_panel.dart';
import 'browser_chip.dart';
import 'browser_frame.dart';
import 'card_image.dart';

/// The chat on screen's everythingllm browser, beside the chat. Where the server says it
/// (`BrowserController`), the tab as one picture read again as it changes, whose it is and what
/// was done last, with Take over to open the browser's take-over view, or Hand back to the agent
/// once it is the person's, and the newest login request that waits, with Open the login form.
/// Where it does not, the newest tab's card in the answers, drawn large and live, and the newest
/// login request's, when no tab's card came after it. Under them, the steps of the answer
/// running in it, or else of the last answer that used it. It follows the chat on screen. A card
/// or picture is followed only while it can be seen, since watching keeps the server's browser
/// from being stopped.
class BrowserPanel extends StatelessWidget {
  const BrowserPanel({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => BrowserStateBuilder(builder: _build);

  Widget _build(BuildContext context, Turn? running) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final known = scope.browser;
    final tab = known.tab;
    final asked = known.waitingLogin;
    // Without the server's word, what the answers show.
    final login = known.browser == null ? scope.chat.loginCard : null;
    final card = known.browser == null ? scope.chat.browserCard : null;
    // The running answer comes first, since it is the chat's newest turn.
    final used = scope.chat.turns.reversed
        .where((turn) => turn.browserSteps.isNotEmpty)
        .firstOrNull;
    return SidePanel(
      title: 'Browser',
      about: running?.browsing ?? false
          ? 'The agent is using it: ${running!.status}'
          : asked != null || login != null
          ? 'The agent is asking you for a login.'
          : tab != null
          ? tab.says
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
            if (asked != null) ...[
              ..._card(
                context,
                BrowserCard(
                  image: asked.card,
                  page: asked.page,
                  title: 'Login request',
                  login: true,
                ),
                action: 'Open the login form',
                help: 'Saves the login for the agent to use; it never sees it.',
              ),
              const SizedBox(height: 16),
            ] else if (login != null) ...[
              ..._card(
                context,
                login,
                action: 'Open the login form',
                help: 'Saves the login for the agent to use; it never sees it.',
              ),
              const SizedBox(height: 16),
            ],
            if (tab != null)
              ..._tab(context, tab, known)
            else if (card != null)
              ..._card(
                context,
                card,
                action: 'Take over',
                help: 'Opens the browser to watch or use it yourself.',
              ),
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

  /// The tab as the server says it: its picture, whose it is and what was done last, then the
  /// button that takes it over, or gives it back to the agent once it is the person's.
  List<Widget> _tab(
    BuildContext context,
    BrowserTab tab,
    BrowserController known,
  ) {
    final t = Tokens.of(context);
    return [
      const BrowserFrame(),
      const SizedBox(height: 12),
      if (tab.title case final title?)
        Text(
          title,
          style: Type.sans(15, weight: FontWeight.w600, color: t.ink),
        ),
      if (tab.site case final site?)
        Text(site, style: Type.sans(12.5, color: t.muted)),
      if (tab.last case final last?) ...[
        const SizedBox(height: 4),
        Text('Last: $last', style: Type.sans(13, color: t.ink2, height: 1.4)),
      ],
      if (known.problem case final problem?) ...[
        const SizedBox(height: 12),
        AlertBox(AlertKind.warn, problem.title, text: problem.text),
      ],
      if (tab.state != 'closed') ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (tab.yours) ...[
              AppButton(
                known.handing ? 'Handing back…' : 'Hand back to the agent',
                primary: true,
                onPressed: known.handing ? null : known.handBack,
              ),
              AppButton(
                'Open the browser',
                onPressed: () => openLink(context, tab.page.toString()),
              ),
            ] else
              AppButton(
                'Take over',
                primary: true,
                onPressed: () => openLink(context, tab.page.toString()),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          tab.yours
              ? 'The agent cannot act while you have it.'
              : 'Opens the browser to watch or use it yourself.',
          style: Type.sans(12.5, color: t.muted),
        ),
      ],
    ];
  }

  /// [card] drawn large and live, with a button that opens its page, saying [action], and [help]
  /// under it.
  List<Widget> _card(
    BuildContext context,
    BrowserCard card, {
    required String action,
    required String help,
  }) {
    final settings = AppScope.of(context).settings;
    return [
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
          action,
          primary: true,
          onPressed: () => openLink(context, card.page.toString()),
        ),
      ),
      const SizedBox(height: 4),
      Text(help, style: Type.sans(12.5, color: Tokens.of(context).muted)),
    ];
  }
}
