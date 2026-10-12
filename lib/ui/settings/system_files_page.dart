import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/system_files.dart';
import '../app_scope.dart';
import '../apps/app_data.dart';
import '../apps/json_view.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/phone_page.dart';
import 'rows.dart';

/// Settings' System files: everything that decides what the agent and the apps do, as the apps
/// server serves it, read only. A folder lists its folders, then its files; a file shows raw
/// with its lines numbered, a JSON file read as JSON unless shown raw. Back steps up a folder
/// at a time, then to Settings.
class SystemFilesPage extends StatelessWidget {
  const SystemFilesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    return ListenableBuilder(
      listenable: shell,
      builder: (context, _) {
        final (:path, :folder) = shell.systemShown;
        return KeyedSubtree(
          key: ValueKey((path, folder)),
          child: folder ? _Folder(path) : _File(path),
        );
      },
    );
  }
}

/// The header over a folder or file at [path]: its name in the mono face, or System files at
/// the top, under Back to what holds it.
Widget _header(BuildContext context, String path, {Widget? action}) {
  final names = path.split('/');
  final above = path.isEmpty
      ? 'Settings'
      : names.length == 1
      ? 'System files'
      : names[names.length - 2];
  return PhonePageHeader(
    title: path.isEmpty ? 'System files' : '',
    heading: path.isEmpty ? null : monoTitle(context, systemTitle(path)),
    back: 'Back to $above',
    onBack: AppScope.of(context).shell.settingsBack,
    action: action,
  );
}

/// One folder: each entry with what it holds, opening it on a tap.
class _Folder extends StatefulWidget {
  const _Folder(this.path);

  final String path;

  @override
  State<_Folder> createState() => _FolderState();
}

class _FolderState extends State<_Folder> {
  late final Future<List<SystemEntry>> _entries = AppScope.of(context).apps
      .systemFolder(widget.path);

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    final path = widget.path;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, path),
        Expanded(
          child: ReadFuture(
            _entries,
            done: (context, entries) => ListView(
              padding: Sizes.pagePadding,
              children: [
                MetaLine(
                  path.isEmpty ? '/' : '$path/',
                  plural(entries.length, 'entry', 'entries'),
                ),
                FieldCard([
                  if (entries.isEmpty) const CardNote('Nothing here.'),
                  for (final entry in entries)
                    EntryRow(
                      icon: entry.folder ? 'folder' : 'doc',
                      name: entry.folder ? '${entry.name}/' : entry.name,
                      about: entry.line(now),
                      onTap: () => shell.showSystemPath(
                        systemPathOf(path, entry.name),
                        folder: entry.folder,
                      ),
                    ),
                ]),
                if (path.isEmpty) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FieldCard.inset,
                    ),
                    child: Text(
                      'Read only. Caches are not listed. Secrets are named in '
                      'settings/ and never shown.',
                      style: Type.note(Tokens.of(context).muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One file, raw with its lines numbered; a JSON file is read as JSON unless shown raw.
class _File extends StatefulWidget {
  const _File(this.path);

  final String path;

  @override
  State<_File> createState() => _FileState();
}

class _FileState extends State<_File> {
  late final Future<String?> _text = AppScope.of(context).apps
      .systemFile(widget.path);
  bool _raw = false;

  @override
  Widget build(BuildContext context) {
    final json = widget.path.endsWith('.json');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          context,
          widget.path,
          action: json
              ? rawButton(context, _raw, () => setState(() => _raw = !_raw))
              : null,
        ),
        Expanded(
          child: ReadFuture(
            _text,
            done: (context, text) => text == null
                ? ListView(
                    padding: Sizes.pagePadding,
                    children: [
                      MetaLine(widget.path, ''),
                      const FieldCard([
                        CardNote('This file is not text, so it is not shown.'),
                      ]),
                    ],
                  )
                : FileText(text, label: widget.path, asJson: json && !_raw),
          ),
        ),
      ],
    );
  }
}
