import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../links.dart';
import '../widgets/sheet.dart';

/// The agent's browser: browser-lean's page for its tab, in a tall sheet over the chat, edge to
/// edge under the drag handle. The page draws its own controls: who has the tab, its address,
/// Logins, taking it over and handing it back. Its Back, Esc, Back on the device, the scrim and
/// a drag down close the sheet.
class BrowserSheet extends StatelessWidget {
  const BrowserSheet(this.tab, {super.key});

  final Uri tab;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final view = scope.appView;
    return SheetFrame(
      title: 'The agent’s browser',
      bare: true,
      height: SheetHeight.tall,
      padding: EdgeInsets.zero,
      onClose: scope.shell.closeBrowser,
      child: view == null
          ? const SizedBox.shrink()
          : view.show(
              tab,
              onLeave: (url) => openLink(context, url.toString()),
              onClose: scope.shell.closeBrowser,
            ),
    );
  }
}
