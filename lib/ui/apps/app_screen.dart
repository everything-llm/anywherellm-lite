import 'package:flutter/material.dart';

import '../../core/apps.dart';
import '../app_scope.dart';
import '../chat/answer_image.dart';
import '../icons.dart';
import '../layout.dart';
import '../links.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/phone_page.dart';
import 'app_data.dart';

/// Shows an app's working page in the device's web view.
abstract interface class AppView {
  /// [page] in a web view that runs its scripts; a link off its host and port goes to
  /// [onLeave].
  Widget show(Uri page, {required void Function(Uri url) onLeave});
}

/// An app full screen, over the home and the chat: Back, its title over its kind and
/// workspace, and More, which opens its data; under them its working page, in the app's own
/// theme, or where the device has no web view its card with a way to the page in the browser.
/// A page of its data shows over it, and Back steps back through them.
class AppScreen extends StatefulWidget {
  const AppScreen(this.app, {super.key});

  final AppRef app;

  @override
  State<AppScreen> createState() => _AppScreenState();
}

class _AppScreenState extends State<AppScreen> {
  @override
  void initState() {
    super.initState();
    final apps = AppScope.of(context).apps;
    // A read tells the controller's listeners at once, so it waits for the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) apps.know(widget.app);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.shell, scope.apps]),
      builder: (context, _) {
        final app = scope.apps.appOf(widget.app);
        final pages = scope.shell.appPages;
        return ColoredBox(
          color: t.bg,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: pages.isNotEmpty,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(app),
                    Expanded(child: _Page(app)),
                  ],
                ),
              ),
              if (pages.isNotEmpty)
                ColoredBox(
                  color: t.bg,
                  child: AppDataPage(
                    pages.last,
                    app: app,
                    key: ValueKey((pages.length, pages.last)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The bar over an app: Back, its title over its kind and workspace, and More.
class _Header extends StatelessWidget {
  const _Header(this.app);

  final ServerApp app;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final workspace =
        scope.chat.workspaces
            .where((w) => w.slug == app.ref.workspace)
            .firstOrNull
            ?.name ??
        app.ref.workspace;
    return PhonePageHeader(
      back: 'Back',
      onBack: scope.shell.closeApp,
      heading: Semantics(
        header: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              app.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.sans(17, weight: FontWeight.w600, color: t.ink),
            ),
            Text(
              '${kindLabel(app.kind)} · $workspace',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.sans(12.5, color: t.muted),
            ),
          ],
        ),
      ),
      action: IconBtn(
        'more',
        tooltip: 'Data and history for ${app.title}',
        box: 48,
        filled: true,
        size: IconSize.small,
        onPressed: () => scope.shell.showAppPage(const AppFolder()),
      ),
    );
  }
}

/// The app's working page in the web view, at the app's own theme, or its card where the
/// device has no web view.
class _Page extends StatelessWidget {
  const _Page(this.app);

  final ServerApp app;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final server = scope.settings.connection?.uri;
    if (server == null) return const SizedBox.shrink();
    final page = themedPage(
      app.page ?? appPage(server, app.ref),
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    if (scope.appView case final view?) {
      return view.show(
        page,
        onLeave: (url) => openLink(context, url.toString()),
      );
    }
    return ListView(
      padding: Sizes.pagePadding,
      children: [
        if (app.card case final card?)
          AnswerImage(
            card,
            alt: app.title,
            server: server,
            linked: true,
            maxHeight: 480,
          ),
        const SizedBox(height: 16),
        ActionRow(even: true, [
          AppButton(
            'Open in the browser',
            icon: 'external',
            onPressed: () => openLink(context, page.toString()),
          ),
        ]),
      ],
    );
  }
}
