import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/apps.dart';
import '../app_scope.dart';
import '../chat/answer_image.dart';
import '../icons.dart';
import '../layout.dart';
import '../links.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/sheet.dart';
import 'app_data.dart';

/// Shows an app's working page in the device's web view.
abstract interface class AppView {
  /// [page] in a web view that runs its scripts; a link off its host and port goes to
  /// [onLeave].
  Widget show(Uri page, {required void Function(Uri url) onLeave});
}

/// An app in a tall sheet over the home or the chat: its title over its kind and workspace, More,
/// which opens its data, and Close; under them its working page, in the app's own theme, or
/// where the device has no web view its card with a way to the page in the browser. Dragging the
/// sheet down or tapping the scrim closes it. A page of its data shows full screen over it, and
/// Back steps back through them.
class AppScreen extends StatefulWidget {
  const AppScreen(this.app, {super.key});

  final AppRef app;

  @override
  State<AppScreen> createState() => _AppScreenState();
}

class _AppScreenState extends State<AppScreen> {
  late final _apps = AppScope.of(context).apps;

  @override
  void initState() {
    super.initState();
    // A read tells the controller's listeners at once, so it waits for the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_apps.check(widget.app));
    });
  }

  @override
  void dispose() {
    // The chat stayed on screen under the sheet, so its card of this app is read again only
    // when the app changed meanwhile, as through its page.
    final apps = _apps;
    final app = widget.app;
    scheduleMicrotask(() => unawaited(apps.check(app)));
    super.dispose();
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
        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: pages.isNotEmpty,
              child: SheetFrame(
                title: app.title,
                about: _about(context, app),
                height: SheetHeight.tall,
                padding: EdgeInsets.zero,
                onClose: scope.shell.closeApp,
                actions: [
                  IconBtn(
                    'more',
                    tooltip: 'Data and history for ${app.title}',
                    box: 44,
                    filled: true,
                    size: IconSize.small,
                    onPressed: () => scope.shell.showAppPage(const AppFolder()),
                  ),
                  const SizedBox(width: 8),
                ],
                child: _Page(app),
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
        );
      },
    );
  }
}

/// The line under an app's title: its kind and its workspace, by name where the server has it.
String _about(BuildContext context, ServerApp app) {
  final workspace =
      AppScope.of(context).chat.workspaces
          .where((w) => w.slug == app.ref.workspace)
          .firstOrNull
          ?.name ??
      app.ref.workspace;
  return '${kindLabel(app.kind)} · $workspace';
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
