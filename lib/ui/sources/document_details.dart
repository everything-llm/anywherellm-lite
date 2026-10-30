import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/sources.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../list_detail.dart';
import '../settings/rows.dart';
import '../shell_popup.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/phone_page.dart';
import '../widgets/scroll_fades.dart';
import '../widgets/sheet.dart';
import '../widgets/tappable.dart';
import 'sources_panel.dart';

/// A document's details as a page of its own, under Document details and Back to Documents: over
/// the Documents sheet on a phone, or filling the Documents pane on a window too narrow for them
/// beside the list.
class DocumentDetailsPage extends StatelessWidget {
  const DocumentDetailsPage(this.name, {super.key});

  /// The document's [SourceFile.storedName].
  final String name;

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Document details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhonePageHeader(
            title: 'Document details',
            back: 'Back to Documents',
            onBack: shell.closeDocument,
          ),
          Expanded(
            child: ScrollFades(
              child: DocumentDetails(name, padding: Sizes.pageIn(context)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A document's details beside Documents' list on a wide window, in a card under Document
/// details, with Close.
class DocumentDetailsCard extends StatelessWidget {
  const DocumentDetailsCard(this.name, {super.key});

  /// The document's [SourceFile.storedName].
  final String name;

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    return DetailCard(
      title: 'Document details',
      actions: [
        IconBtn(
          'close',
          tooltip: 'Close details',
          onPressed: shell.closeDocument,
        ),
      ],
      child: SheetCards(
        child: ScrollFades(
          child: DocumentDetails(
            name,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          ),
        ),
      ),
    );
  }
}

/// What Document details shows of the document stored as [name]: its title; whether the open
/// workspace answers from it, whether it reads it in full, and its folder, which opens Move to
/// folder; its kind, words, when it was added and where it came from; then Delete from server,
/// which asks first. Once the library no longer has it, as after it was deleted, the details
/// close. Folders are not deleted here, since that deletes the documents in them.
class DocumentDetails extends StatelessWidget {
  const DocumentDetails(this.name, {super.key, required this.padding});

  final String name;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sources = scope.sources;
    return ListenableBuilder(
      listenable: sources,
      builder: (context, _) {
        final file = sources.byName(name);
        if (file == null) {
          // Gone from the library once it is read: there is nothing left to show.
          if (!sources.loading) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final shell = scope.shell;
              if (shell.document == name &&
                  sources.byName(name) == null &&
                  !sources.loading) {
                shell.closeDocument();
              }
            });
          }
          return const SizedBox.shrink();
        }
        return _Shown(file, padding: padding);
      },
    );
  }
}

class _Shown extends StatelessWidget {
  const _Shown(this.file, {required this.padding});

  final SourceFile file;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final sources = scope.sources;
    final t = Tokens.of(context);
    final words = file.words;
    final added = file.added;
    final from = file.from;
    final details = ListView(
      padding: padding,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: FieldCard.inset),
          child: Semantics(
            header: true,
            child: Text(
              file.title,
              style: Type.body(t.ink, weight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FieldCard([
          FieldRow.toggle(
            label: 'Used in answers',
            value: file.on,
            onChanged: (_) => unawaited(sources.toggle(file)),
          ),
          // Only a document the workspace answers from can be read in full.
          FieldRow.toggle(
            label: readInFull,
            help: 'Answers get the whole document, not only the closest passages.',
            value: file.pinned,
            onChanged: file.on
                ? (whole) => unawaited(sources.readWhole(file, whole))
                : null,
          ),
          _FolderRow(
            file.folder,
            onTap: () => shell.togglePopup(Popup.moveDocument),
          ),
        ]),
        const SizedBox(height: 16),
        FieldCard([
          _Fact('Kind', lead: TypeTile(file)),
          if (words != null) _Fact('Words', value: grouped(words)),
          if (added != null) _Fact('Added', value: added),
          _Fact(
            'Source',
            value: file.origin.label,
            under: from,
            mono: file.origin == DocOrigin.web,
          ),
        ]),
        const SizedBox(height: 16),
        AppButton(
          'Delete from server',
          danger: true,
          quiet: true,
          onPressed: () => shell.togglePopup(Popup.deleteDocument),
        ),
      ],
    );
    return ShellPopup(
      popup: Popup.moveDocument,
      title: 'Move to folder',
      subject: file.storedName,
      builder: (context, close) => _MoveSheet(file, close: close),
      child: ShellPopup(
        popup: Popup.deleteDocument,
        title: 'Delete from server',
        subject: file.storedName,
        builder: (context, close) => SheetQuestion(
          'Delete ${file.title} from the server? Every workspace loses it. This can\'t be '
          'undone.',
          action: 'Delete from server',
          onKeep: close,
          onConfirm: () {
            close();
            shell.closeDocument();
            unawaited(sources.delete(file));
          },
        ),
        child: details,
      ),
    );
  }
}

/// The row of the folder a document is in, its name at the row's end, which opens Move to
/// folder.
class _FolderRow extends StatelessWidget {
  const _FolderRow(this.folder, {required this.onTap});

  final String folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: 'Folder: $folder. Move to another folder',
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(
          minHeight: SheetFrame.holds(context) ? Sizes.cardRow : Sizes.pageRow,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: FieldCard.inset,
          vertical: 8,
        ),
        child: Row(
          spacing: 12,
          children: [
            Text('Folder', style: Type.body(t.ink)),
            Expanded(
              child: Text(
                folder,
                textAlign: TextAlign.end,
                style: Type.body(t.ink),
              ),
            ),
            AppIcon('chevron', size: IconSize.xs, color: t.muted),
          ],
        ),
      ),
    );
  }
}

/// One thing about a document: its [term] in muted, and at the row's end its [value], with
/// [under] beneath it in the mono face when [mono], as an address is, or [lead] in its place.
class _Fact extends StatelessWidget {
  const _Fact(
    this.term, {
    this.value,
    this.under,
    this.lead,
    this.mono = false,
  });

  final String term;
  final String? value;
  final String? under;
  final Widget? lead;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return MergeSemantics(
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(
          horizontal: FieldCard.inset,
          vertical: 8,
        ),
        child: Row(
          spacing: 12,
          children: [
            Text(term, style: Type.body(t.muted)),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child:
                    lead ??
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          value ?? '',
                          textAlign: TextAlign.end,
                          style: Type.body(t.ink),
                        ),
                        // An address shows whole, on as many lines as it takes.
                        if (under case final under?)
                          Text(
                            under,
                            textAlign: TextAlign.end,
                            style: mono
                                ? Type.mono(13, color: t.ink, height: 1.4)
                                : Type.note(t.ink),
                          ),
                      ],
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Move to folder: the library's folders, the one [file] is in chosen, and New folder, whose
/// Create makes one and chooses it; Move moves [file] into the one chosen and closes.
class _MoveSheet extends StatefulWidget {
  const _MoveSheet(this.file, {required this.close});

  final SourceFile file;
  final VoidCallback close;

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  late String _picked = widget.file.folder;
  final _name = TextEditingController();

  /// Why the last folder could not be made, or null.
  String? _problem;
  bool _making = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (_making) return;
    setState(() => _making = true);
    final problem = await AppScope.of(context).sources.createFolder(name);
    if (!mounted) return;
    setState(() {
      _making = false;
      _problem = problem;
      if (problem == null) {
        _picked = name;
        _name.clear();
      }
    });
  }

  void _move() {
    final sources = AppScope.of(context).sources;
    widget.close();
    unawaited(sources.move(widget.file, _picked));
  }

  @override
  Widget build(BuildContext context) {
    final sources = AppScope.of(context).sources;
    return ListenableBuilder(
      listenable: sources,
      builder: (context, _) {
        // The folder chosen shows though a read has not listed it yet, as one just made.
        final folders = {...sources.folders, widget.file.folder, _picked};
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    Semantics(
                      container: true,
                      label: 'Folder',
                      child: FieldCard([
                        for (final folder in folders)
                          CardRow(
                            folder,
                            checked: folder == _picked,
                            onTap: () => setState(() => _picked = folder),
                          ),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: NamedControl(
                        'New folder',
                        labelled: true,
                        Row(
                          spacing: 8,
                          children: [
                            Expanded(
                              child: AppField(
                                controller: _name,
                                label: 'New folder',
                                hint: 'Folder name',
                                onSubmitted: (_) => unawaited(_create()),
                              ),
                            ),
                            AppButton(
                              'Create',
                              onPressed: _making
                                  ? null
                                  : () => unawaited(_create()),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_problem case final problem?)
                      AlertBox(
                        AlertKind.bad,
                        'Could not make the folder',
                        text: problem,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            AppButton('Move', primary: true, onPressed: _move),
          ],
        );
      },
    );
  }
}
