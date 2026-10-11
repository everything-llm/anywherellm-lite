import 'package:flutter/material.dart';

import '../../core/chat.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../links.dart';
import '../widgets/buttons.dart';
import '../widgets/side_panel.dart';
import 'card_image.dart';

/// What the panel or sheet says an app is, after its name: an app, and the workspace whose
/// data it shows, by the workspace's name when this server has it.
String _kindOf(BuildContext context, AppCard app) {
  final workspace = AppScope.of(context).chat.workspaces
      .where((w) => w.slug == app.workspace)
      .firstOrNull;
  return 'App · ${workspace?.name ?? app.workspace}';
}

/// Where [app]'s page opens in the app: in the app's theme, so the page matches it whatever the
/// device's. The sheet shows it and the chat fetches it ahead at this one address.
Uri appPageOf(BuildContext context, AppCard app) => themedPage(
  app.page,
  light: Theme.of(context).brightness == Brightness.light,
);

/// The app's live card, drawn large. It is followed only while it can be seen, as every card
/// is.
Widget _card(BuildContext context, AppCard app) {
  final settings = AppScope.of(context).settings;
  return CardImage(
    app.card,
    key: ValueKey(app.card),
    alt: app.name,
    server: settings.connection?.uri,
    allowHttp: settings.allowHttp,
    linked: true,
    maxHeight: 640,
  );
}

/// The app an answer's card opened, beside the chat in the browser's place, or as a sheet over
/// the chat on a phone: its name and kind, its live card drawn large, Open in the browser, which
/// opens its page, and Close, which puts back what the panel showed. Beside the chat it only
/// shows the app; changing it happens on its page. The sheet shows that page itself where the
/// device has a web view ([AppScope.appView]). Dragging the sheet down, or a tap on the scrim,
/// closes it.
class AppPanel extends StatelessWidget {
  const AppPanel({super.key, required this.app, required this.width});

  final AppCard app;
  final double width;

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    // A phone's is a sheet over the chat.
    final sheet = ScreenClass.ofContext(context).isPhone;
    return SidePanel(
      title: app.name,
      about: _kindOf(context, app),
      aboutBeside: true,
      width: width,
      onClose: shell.closeApp,
      actions: [
        IconBtn(
          'external',
          tooltip: 'Open in the browser',
          box: sheet ? 44 : 28,
          size: sheet ? IconSize.small : IconSize.xs,
          onPressed: () => openLink(context, app.page.toString()),
        ),
        if (!sheet) const SizedBox(width: 2),
      ],
      child: switch (AppScope.of(context).appView) {
        // On a phone with a web view, the app's own page, which can change it.
        final view? when sheet => view.show(
          appPageOf(context, app),
          placeholder: _card(context, app),
          onLeave: (url) => openLink(context, url.toString()),
        ),
        _ => SingleChildScrollView(child: _card(context, app)),
      },
    );
  }
}
