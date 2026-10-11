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
        final count = created.list?.files.length;
        return DrawerRow(
          icon: 'grid',
          title: 'Artifacts',
          heard: count == null
              ? 'Artifacts'
              : 'Artifacts, ${plural(count, 'file', 'files')}',
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

/// A phone's Artifacts: the files the agent's code left in the open workspace, newest first,
/// under how much of the workspace's room is used. A row opens its [CreatedSheet]. It shows the
/// read the drawer made as it opened, or makes one, and reads again on its refresh button.
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
              if (list != null)
                Text(plural(list.files.length, 'file', 'files'), style: small),
            ],
          ),
        ),
        if (created.problem case final problem?) ...[
          const SizedBox(height: 16),
          AlertBox(AlertKind.bad, problem.title, text: problem.text),
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

/// A phone's sheet for one created file, over the window: Download, Open page for a page on the
/// web, Keep for a working file, and Delete file, which asks first.
class CreatedSheet extends StatelessWidget {
  const CreatedSheet(this.of, {super.key});

  final CreatedSheetFor of;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final file = of.file;
    final created = scope.created;
    final shell = scope.shell;
    return ModalSheet(
      title: of.deleting ? 'Delete file' : file.name,
      onClose: shell.closePopup,
      child: of.deleting
          ? _Delete(file)
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  FieldCard(inSheet: true, [
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
                          unawaited(created.keep(file));
                        },
                      ),
                  ]),
                  FieldCard(inSheet: true, [
                    CardRow(
                      'Delete file',
                      icon: 'trash',
                      tone: RowTone.danger,
                      onTap: () => shell.openCreatedSheet(file, deleting: true),
                    ),
                  ]),
                ],
              ),
            ),
    );
  }
}

/// The question before a created file is deleted.
class _Delete extends StatelessWidget {
  const _Delete(this.file);

  final CreatedFile file;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return SheetQuestion(
      deleteCreatedQuestion(file),
      onKeep: scope.shell.closePopup,
      onDelete: () {
        scope.shell.closePopup();
        unawaited(scope.created.remove(file));
      },
    );
  }
}
