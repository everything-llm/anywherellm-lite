import 'package:flutter/material.dart';

import '../../core/browser.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/tappable.dart';

/// A browser tab's card in an answer on a phone, drawn as the app's item rather than the
/// server's picture: the page's title over Browser, who has the tab and its site as the server
/// says them, and Open browser, which opens the chat's browser. Without the server's word it
/// names the page as the card does.
class BrowserItem extends StatelessWidget {
  const BrowserItem(this.card, {super.key});

  final BrowserCard card;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: scope.browser,
      builder: (context, _) {
        // The server's word, when it is about this card's tab.
        final tab = switch (scope.browser.tab) {
          final tab? when tab.id == card.tab => tab,
          _ => null,
        };
        final title = tab?.title ?? card.title.replaceFirst('Browser: ', '');
        final line = tab == null ? null : browserItemLine(tab);
        return Tappable(
          label: 'Open the browser: $title${line == null ? '' : '. $line'}',
          onTap: scope.shell.showBrowser,
          radius: BorderRadius.circular(Sizes.phoneCard),
          child: Container(
            decoration: BoxDecoration(
              color: t.panel,
              border: Border.all(color: t.line2),
              borderRadius: BorderRadius.circular(Sizes.phoneCard),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    line == null ? 14 : 4,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Type.sans(
                            17,
                            weight: FontWeight.w600,
                            color: t.ink,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Browser',
                        style: Type.sans(
                          12,
                          weight: FontWeight.w600,
                          color: t.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (line != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
                    child: Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.sans(13, color: t.muted, height: 1.45),
                    ),
                  ),
                Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.line2)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Open browser',
                          style: Type.sans(
                            16,
                            weight: FontWeight.w500,
                            color: t.accent,
                          ),
                        ),
                      ),
                      AppIcon('chevron', size: IconSize.xs, color: t.accent),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
