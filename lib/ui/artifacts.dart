import 'dart:async';

import 'package:flutter/material.dart';

import '../core/copy.dart';
import '../core/created.dart';
import 'app_scope.dart';
import 'files/created_files.dart';
import 'icons.dart';
import 'links.dart';
import 'settings/rows.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/basics.dart';
import 'widgets/buttons.dart';
import 'widgets/drawer_row.dart';
import 'widgets/fields.dart';
import 'widgets/phone_page.dart';
import 'widgets/sheet.dart';
import 'widgets/tappable.dart';

/// Artifacts in a phone's drawer, with how many files the agent's code left in the open
/// workspace once read. It reads them afresh each time the drawer opens, so [ArtifactsPage]
/// opens on that read, and is left out on a server whose host does not list them.
class ArtifactsRow extends StatefulWidget {
  const ArtifactsRow({super.key});

  @override
  State<ArtifactsRow> createState() => _ArtifactsRowState();
}

class _ArtifactsRowState extends State<ArtifactsRow> {
  late final _scope = AppScope.of(context);

  /// Whether the drawer was open at the shell's last change.
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = _scope.shell.sideOpen;
    _scope.shell.addListener(_drawerChanged);
  }

  @override
  void dispose() {
    _scope.shell.removeListener(_drawerChanged);
    super.dispose();
  }

  void _drawerChanged() {
    final open = _scope.shell.sideOpen;
    final created = _scope.created;
    if (open && !_open && !created.unavailable && !created.loading) {
      unawaited(created.read());
    }
    _open = open;
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    return ListenableBuilder(
      listenable: scope.created,
      builder: (context, _) {
        final created = scope.created;
        if (created.unavailable) return const SizedBox.shrink();
        final list = created.list;
        final count = list == null
            ? null
            : list.files.length + (list.apps?.length ?? 0);
        return DrawerRow(
          icon: 'grid',
          title: 'Artifacts',
          heard: list == null ? 'Artifacts' : 'Artifacts, ${_counts(list)}',
          iconSize: IconSize.small,
          trailing: count == null ? null : DrawerCount('$count'),
          onTap: () {
            scope.shell
              ..closeSide()
              ..openPhonePage(PhonePage.artifacts);
          },
        );
      },
    );
  }
}

/// How many apps and files [list] has: `2 apps · 4 files`, or the files alone from a host that
/// does not list apps.
String _counts(CreatedList list) => [
  if (list.apps case final apps?) plural(apps.length, 'app', 'apps'),
  plural(list.files.length, 'file', 'files'),
].join(' · ');

/// A phone's Artifacts: the open workspace's apps, then the files the agent's code left in it,
/// newest first, under how much of the workspace's room is used. An app's row opens the app and
/// a file's row its [CreatedSheet]. It shows the read the drawer made as it opened, or makes
/// one, and reads again on its refresh button.
class ArtifactsPage extends StatelessWidget {
  const ArtifactsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final created = scope.created..want();
    return ColoredBox(
      color: t.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhonePageHeader(
            title: 'Artifacts',
            back: 'Back to the chat',
            onBack: scope.shell.closePhonePage,
            action: IconBtn(
              'refresh',
              tooltip: 'Read the list again',
              box: 48,
              filled: true,
              size: IconSize.small,
              onPressed: () {
                if (!created.loading) unawaited(created.read());
              },
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: created,
              builder: (context, _) => _body(scope, t),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(AppScope scope, Tokens t) {
    final created = scope.created;
    final list = created.list;
    final now = DateTime.now();
    final muted = Type.sans(14, color: t.muted);
    final small = Type.sans(13, color: t.muted);
    Widget note(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: child,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: FieldCard.inset),
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: scope.chat,
                  builder: (context, _) => Text(
                    scope.chat.active?.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: small,
                  ),
                ),
              ),
              if (list != null) Text(_counts(list), style: small),
            ],
          ),
        ),
        if (created.problem case final problem?) ...[
          const SizedBox(height: 16),
          AlertBox(AlertKind.bad, problem.title, text: problem.text),
        ],
        if (list?.apps case final apps?) ...[
          const Padding(
            padding: EdgeInsets.only(top: 20, bottom: 8),
            child: CardHeading('Apps'),
          ),
          FieldCard([
            if (apps.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FieldCard.inset,
                  vertical: 20,
                ),
                child: Text('No apps in this workspace yet.', style: muted),
              ),
            for (final app in apps)
              _AppRow(
                app,
                key: ValueKey(app.id),
                working: created.working.contains(app.id),
              ),
          ]),
        ],
        const Padding(
          padding: EdgeInsets.only(top: 20, bottom: 8),
          child: CardHeading('Created files'),
        ),
        if (created.unavailable)
          note(
            Text(
              'This server has no list of them. Each file shows under the answer that made '
              'it, where it can be saved.',
              style: muted,
            ),
          )
        else if (list == null)
          note(
            Text(created.loading ? 'Reading…' : 'Not read yet.', style: muted),
          )
        else
          FieldCard([
            Container(
              constraints: const BoxConstraints(minHeight: 76),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: FieldCard.inset),
              child: CreatedMeter(list, large: true),
            ),
            if (list.files.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FieldCard.inset,
                  vertical: 20,
                ),
                child: Text('No created files yet.', style: muted),
              ),
            for (final file in list.files)
              _FileRow(
                file,
                key: ValueKey(file.id),
                now: now,
                working: created.working.contains(file.id),
              ),
          ]),
        if (list?.truncated ?? false) ...[
          const SizedBox(height: 12),
          note(const HelpText('Only the newest files are listed.')),
        ],
        const SizedBox(height: 16),
        note(
          const HelpText(
            'A working file goes 7 days after its chat last used it, unless you keep it.',
          ),
        ),
      ],
    );
  }
}

/// One app: its title over its kind and how it stands, which opens it, and a More button that
/// opens its [CreatedSheet].
class _AppRow extends StatelessWidget {
  const _AppRow(this.app, {super.key, required this.working});

  final CreatedApp app;

  /// Whether the app is being deleted.
  final bool working;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final about = working ? 'Working…' : app.about;
    return Padding(
      padding: const EdgeInsets.only(left: FieldCard.inset, right: 8),
      child: Row(
        spacing: 4,
        children: [
          Expanded(
            child: Tappable(
              label: [app.title, if (about.isNotEmpty) about].join(', '),
              onTap: working || !_canOpen(app) ? null : () => _open(scope, app),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                        app.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.sans(16, weight: FontWeight.w500),
                      ),
                      if (about.isNotEmpty)
                        Text(
                          about,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Type.sans(
                            13,
                            color: app.error == null ? t.muted : t.badfg,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconBtn(
            'more',
            tooltip: 'Open in the browser or delete ${app.title}',
            box: 44,
            size: IconSize.small,
            onPressed: working ? null : () => scope.shell.openCreatedSheet(app),
          ),
        ],
      ),
    );
  }
}

/// Whether [app] can open in the app's own sheet: it needs its live card and the card's link.
bool _canOpen(CreatedApp app) => app.card != null && app.link != null;

/// Opens [app] as its card in a chat does, in place of the Artifacts page.
void _open(AppScope scope, CreatedApp app) {
  final slug = scope.chat.activeSlug;
  if (slug == null) return;
  scope.shell
    ..closePopup()
    ..closePhonePage()
    ..showApp((
      card: app.card!,
      page: app.link!,
      name: app.title,
      workspace: slug,
    ));
}

/// One file: its name over [createdMeta] and its mark, when it has one, and a More icon. The
/// whole row opens its [CreatedSheet].
class _FileRow extends StatelessWidget {
  const _FileRow(
    this.file, {
    super.key,
    required this.now,
    required this.working,
  });

  final CreatedFile file;
  final DateTime now;

  /// Whether the file is being kept or deleted.
  final bool working;

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    final t = Tokens.of(context);
    final mark = createdMark(file, now);
    final meta = createdMeta(file, now, address: false);
    return Tappable(
      label: [
        file.name,
        meta,
        ?mark,
        if (working) 'working',
        'Download',
        if (file.isPage) 'open page',
        if (file.area == CreatedArea.work) 'keep',
        'or delete',
      ].join(', '),
      onTap: working ? null : () => shell.openCreatedSheet(file),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.only(left: FieldCard.inset, right: 8),
        child: Row(
          spacing: 4,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.sans(16, weight: FontWeight.w500),
                    ),
                    // The line gives way before the mark does.
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            working ? 'Working…' : meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Type.sans(13, color: t.muted),
                          ),
                        ),
                        if (mark != null && !working)
                          Text(
                            ' · $mark',
                            maxLines: 1,
                            style: Type.sans(
                              13,
                              color: file.area == CreatedArea.work
                                  ? t.badfg
                                  : t.okfg,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox.square(
              dimension: 44,
              child: Center(
                child: AppIcon('more', size: IconSize.small, color: t.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A phone's sheet for one created file or app, over the window. A file's: Download, Open page
/// for a page on the web, Keep for a working file, and Delete file. An app's: Open, Open in the
/// browser and Delete app. Either delete asks first.
class CreatedSheet extends StatelessWidget {
  const CreatedSheet(this.of, {super.key});

  final CreatedSheetFor of;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final item = of.item;
    final shell = scope.shell;
    final (actions, delete) = switch (item) {
      CreatedFile() => (_fileActions(context, item), 'Delete file'),
      CreatedApp() => (_appActions(context, item), 'Delete app'),
    };
    return ModalSheet(
      title: of.deleting ? delete : item.label,
      onClose: shell.closePopup,
      child: of.deleting
          ? SheetQuestion(
              deleteCreatedQuestion(item),
              onKeep: shell.closePopup,
              onDelete: () {
                shell.closePopup();
                unawaited(scope.created.remove(item));
              },
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  if (actions.isNotEmpty) FieldCard(inSheet: true, actions),
                  FieldCard(inSheet: true, [
                    CardRow(
                      delete,
                      icon: 'trash',
                      tone: RowTone.danger,
                      onTap: () => shell.openCreatedSheet(item, deleting: true),
                    ),
                  ]),
                ],
              ),
            ),
    );
  }

  List<Widget> _fileActions(BuildContext context, CreatedFile file) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    return [
      CardRow(
        'Download',
        icon: 'download',
        onTap: () {
          shell.closePopup();
          unawaited(saveCreated(context, file));
        },
      ),
      if (file.isPage)
        CardRow(
          'Open page',
          icon: 'external',
          onTap: () {
            shell.closePopup();
            unawaited(openLink(context, file.url!));
          },
        ),
      if (file.area == CreatedArea.work)
        CardRow(
          'Keep',
          icon: 'check',
          onTap: () {
            shell.closePopup();
            unawaited(scope.created.keep(file));
          },
        ),
    ];
  }

  List<Widget> _appActions(BuildContext context, CreatedApp app) {
    final scope = AppScope.of(context);
    final page = app.page;
    return [
      if (_canOpen(app))
        CardRow('Open', icon: 'grid', onTap: () => _open(scope, app)),
      if (page != null)
        CardRow(
          'Open in the browser',
          icon: 'external',
          onTap: () {
            scope.shell.closePopup();
            unawaited(openLink(context, page.toString()));
          },
        ),
    ];
  }
}
