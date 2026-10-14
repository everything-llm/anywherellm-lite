import 'package:flutter/widgets.dart';

import '../app_scope.dart';
import '../links.dart';
import '../widgets/sheet.dart';

/// A page on the connected server that an answer links to, such as an apps-lean app's page, in
/// a tall sheet over the chat: the page edge to edge under the drag handle, drawing its own
/// controls. Esc, Back on the device, the scrim and a drag down close it, and so does the page's
/// own `window.close()`.
class PageSheet extends StatelessWidget {
  const PageSheet(this.page, {super.key});

  final Uri page;

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
              page,
              onLeave: (url) => openLink(context, url.toString()),
              onClose: scope.shell.closePage,
            ),
    );
  }
}
