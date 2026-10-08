import 'package:flutter/material.dart';

import '../../core/chat.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../links.dart';
import '../tokens.dart';
import '../type.dart';
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

/// The app an answer's card opened, beside the chat in the browser's place: its name and kind,
/// its live card drawn large, Open in the browser, which opens its page, and Close, which puts
/// back what the panel showed. It only shows the app; changing it happens on its page.
class AppPanel extends StatelessWidget {
  const AppPanel({super.key, required this.app, required this.width});

  final AppCard app;
  final double width;

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
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
          box: 28,
          size: IconSize.xs,
          onPressed: () => openLink(context, app.page.toString()),
        ),
        const SizedBox(width: 2),
      ],
      child: SingleChildScrollView(child: _card(context, app)),
    );
  }
}

/// The app an answer's card opened, on a phone: a sheet over the chat, under a drag handle, with
/// its name and kind, Open in the browser and Close, and its live card drawn large. Dragging it
/// down, or a tap on the scrim, closes it.
class AppSheet extends StatefulWidget {
  const AppSheet({super.key, required this.app});

  final AppCard app;

  /// The room left above the sheet, where the chat shows through the scrim.
  static const gap = 72.0;

  @override
  State<AppSheet> createState() => _AppSheetState();
}

class _AppSheetState extends State<AppSheet> {
  /// How far the sheet has been dragged down. Only the sheet's place follows it, not the sheet.
  final _drag = ValueNotifier<double>(0);

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  void _dragged(DragUpdateDetails details) =>
      _drag.value = (_drag.value + details.delta.dy).clamp(0, 10000);

  void _let(DragEndDetails details) {
    if (_drag.value > 120 || details.velocity.pixelsPerSecond.dy > 700) {
      AppScope.of(context).shell.closeApp();
    } else {
      _drag.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final app = widget.app;
    final shell = AppScope.of(context).shell;
    final header = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _dragged,
      onVerticalDragEnd: _let,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: t.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.line2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          app.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Type.sans(
                            17,
                            weight: FontWeight.w600,
                            color: t.ink,
                            height: 1.3,
                          ),
                        ),
                      ),
                      Text(
                        _kindOf(context, app),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.sans(12.5, color: t.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconBtn(
                  'external',
                  tooltip: 'Open in the browser',
                  box: 44,
                  size: IconSize.small,
                  onPressed: () => openLink(context, app.page.toString()),
                ),
                IconBtn(
                  'close',
                  tooltip: 'Close',
                  box: 44,
                  size: IconSize.small,
                  onPressed: shell.closeApp,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return ValueListenableBuilder(
      valueListenable: _drag,
      builder: (context, drag, sheet) => Positioned(
        left: 0,
        right: 0,
        top: AppSheet.gap + drag,
        bottom: -drag,
        child: sheet!,
      ),
      child: Semantics(
        container: true,
        label: app.name,
        child: Container(
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: t.shadow,
                blurRadius: 26,
                spreadRadius: -12,
                offset: const Offset(0, -12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: _card(context, app),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
