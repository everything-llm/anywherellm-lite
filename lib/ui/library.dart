import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/files.dart';
import '../core/library.dart';
import '../core/outputs.dart';
import '../core/schedule.dart';
import '../core/upload.dart';
import 'app_scope.dart';
import 'chat/generated_files.dart';
import 'layout.dart';
import 'links.dart';
import 'settings/rows.dart';
import 'sources/sources_panel.dart';
import 'state/toolkit_controller.dart';
import 'toolkit_page.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/buttons.dart';
import 'widgets/phone_page.dart';
import 'widgets/segmented.dart';
import 'widgets/tappable.dart';

/// What the agent made: its apps, which a tap opens in their sheet, and its files, which save and
/// share. It shows the open workspace's, or every workspace's with its switch. Read only. It
/// reads the Library afresh as it opens, from the toolkit.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  bool _files = false;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ToolkitPageFrame(
      title: 'Library',
      read: scope.toolkit.readLibrary,
      action: ToolkitPageFrame.readAgain(scope.toolkit.readLibrary),
      body: ListenableBuilder(
        listenable: Listenable.merge([scope.toolkit, scope.chat]),
        builder: (context, _) => _body(context, scope.toolkit),
      ),
    );
  }

  Widget _body(BuildContext context, ToolkitController toolkit) {
    final scope = AppScope.of(context);
    final contents = toolkit.library;
    final slug = scope.chat.activeSlug;
    final name = scope.chat.active?.name;
    // The open workspace's first, then the rest, in the order the toolkit gave them.
    List<T> shown<T>(List<T> all, bool Function(T) here) => [
      ...all.where((x) => here(x)),
      if (_all) ...all.where((x) => !here(x)),
    ];
    final apps = shown(contents?.apps ?? const [], (a) => a.isIn(slug));
    final files = shown(contents?.files ?? const [], (f) => f.isIn(slug));
    return ListView(
      padding: Sizes.pagePadding,
      children: [
        if (contents == null || toolkit.libraryProblem != null)
          NotRead(toolkit.libraryProblem)
        else ...[
          Segmented<bool>(
            options: [
              (false, 'Apps · ${apps.length}'),
              (true, 'Files · ${files.length}'),
            ],
            value: _files,
            onChanged: (files) => setState(() => _files = files),
          ),
          const SizedBox(height: 20),
          FieldCard([
            FieldRow.toggle(
              label: 'All workspaces',
              help: _all
                  ? 'Every workspace${name == null ? '' : ', $name first'}'
                  : 'Only ${name ?? 'this workspace'}',
              value: _all,
              onChanged: (on) => setState(() => _all = on),
            ),
          ]),
          const SizedBox(height: 20),
          if ((_files ? files.isEmpty : apps.isEmpty))
            const FieldCard([
              CardNote(
                'Nothing here yet. Ask the agent to build an app or make a file.',
              ),
            ])
          else if (_files)
            FieldCard([
              for (final f in files)
                _FileRow(
                  f,
                  showWorkspace: _all,
                  key: ValueKey(f.file.storageName),
                ),
            ])
          else
            FieldCard([for (final a in apps) _AppRow(a, showWorkspace: _all)]),
          const SizedBox(height: 12),
          CardCaption(
            _files ? 'Files the agent made in chats. Read only here.' : 'Each line says what changed last, never what is in the app now. Open an app to see it.',
          ),
        ],
      ],
    );
  }
}

/// An app: its title over what changed in it last and when, which a tap opens in its sheet.
class _AppRow extends StatelessWidget {
  const _AppRow(this.app, {required this.showWorkspace});

  final LibraryApp app;
  final bool showWorkspace;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final changed = app.changed;
    final about = [
      if (showWorkspace) ?app.workspace,
      if (app.change.isNotEmpty) app.change,
      if (changed != null) dayText(changed, now),
    ].join(' · ');
    return NavRow(
      title: app.title,
      about: about,
      heard: '${app.title}, $about. Open the app',
      onTap: () => unawaited(openAnswerLink(context, app.page)),
    );
  }
}

/// A file: its type, name, size and where it was made, Save and Share. A picture's row opens it
/// over the window.
class _FileRow extends StatefulWidget {
  const _FileRow(this.item, {super.key, required this.showWorkspace});

  final LibraryFile item;
  final bool showWorkspace;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  Uint8List? _bytes;

  Future<void> _open() async {
    final scope = AppScope.of(context);
    final file = widget.item.file;
    final bytes = await scope.chat.bytes.file(file);
    if (!mounted || bytes == null) return;
    setState(() => _bytes = bytesOf(bytes));
    scope.shell.togglePopup(file);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final item = widget.item;
    final file = item.file;
    final created = item.created;
    final now = DateTime.now();
    final about = [
      if (file.size case final size?) sizeText(size),
      if (widget.showWorkspace) ?item.workspace,
      if (created != null) dayText(created, now),
    ].join(' · ');
    final row = Row(
      children: [
        Expanded(
          child: Tappable(
            label: '${file.name}, $about${file.isImage ? '. Open' : ''}',
            onTap: file.isImage ? _open : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: Sizes.cardRow),
              padding: const EdgeInsets.fromLTRB(FieldCard.inset, 10, 0, 10),
              child: Row(
                spacing: 12,
                children: [
                  TypeTile.label(sourceExt(file.name)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Type.sans(
                            16,
                            weight: FontWeight.w500,
                            color: t.ink,
                          ),
                        ),
                        if (about.isNotEmpty)
                          Text(
                            about,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Type.sans(13, color: t.muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconBtn(
          'download',
          tooltip: 'Save ${file.name}',
          box: 44,
          onPressed: () => unawaited(saveMadeFile(context, file)),
        ),
        if (scope.share != null)
          IconBtn(
            'share',
            tooltip: 'Share ${file.name}',
            box: 44,
            onPressed: () => unawaited(shareMadeFile(context, file)),
          ),
        const SizedBox(width: 12),
      ],
    );
    final bytes = _bytes;
    if (bytes == null) return row;
    return ViewerWhileOpen(file, bytes, child: row);
  }
}
