import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/apps.dart';
import '../../core/connection.dart';
import '../app_scope.dart';
import '../chat/answer_image.dart';
import '../layout.dart';
import '../links.dart';
import '../tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/sheet.dart';
import 'app_data.dart';

/// Shows an app's working page in the device's web view.
abstract interface class AppView {
  /// [page] in a web view that runs its scripts; a link off its host and port goes to
  /// [onLeave], and the page closing itself (`window.close()`) to [onClose].
  Widget show(
    Uri page, {
    required void Function(Uri url) onLeave,
    VoidCallback? onClose,
  });
}

/// An app in a tall sheet over the home or the chat: its title over its kind and workspace, and
/// Close; under them its working page, in the app's own theme, or
/// where the device has no web view its card with a way to the page in the browser. Dragging the
/// sheet down or tapping the scrim closes it. Its data, opened from the Apps tab's menu, shows
/// full screen alone, and Back steps back through its pages.
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

  /// Whether the app's sheet showed last, rather than its data alone.
  bool _sheet = true;

  @override
  void dispose() {
    // The chat stayed on screen under the sheet, so its card of this app is read again only
    // when the app changed meanwhile, as through its page.
    if (_sheet) {
      final apps = _apps;
      final app = widget.app;
      scheduleMicrotask(() => unawaited(apps.check(app)));
    }
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
        _sheet = pages.isEmpty;
        if (_sheet) {
          return SheetFrame(
            title: app.title,
            about: _about(context, app),
            height: SheetHeight.tall,
            padding: EdgeInsets.zero,
            onClose: scope.shell.closeApp,
            child: _Page(app),
          );
        }
        return ColoredBox(
          color: t.bg,
          child: AppDataPage(
            pages.last,
            app: app,
            key: ValueKey((pages.length, pages.last)),
          ),
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
    final pages = scope.apps.pages;
    if (server == null || pages == null) return const SizedBox.shrink();
    final page = themedPage(
      app.page ?? appPage(pages, app.ref),
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    // Android lets the web view load plain http; the app's own rule keeps it to private hosts.
    if (scope.appView case final view? when keySafe(page)) {
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
            cards: scope.apps.cards,
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
