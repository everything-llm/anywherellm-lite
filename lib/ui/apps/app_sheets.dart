import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/apps.dart';
import '../../core/ports.dart';
import '../app_scope.dart';
import '../settings/rows.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/sheet.dart';
import 'app_data.dart';
import 'json_view.dart';

/// A sheet about one app, kept in the shell's popup: what it opens over the window.
sealed class AppSheet {
  const AppSheet(this.app);

  final AppRef app;
}

/// An app's menu in the Apps tab: Open, Rename and Delete app.
class AppMenuSheet extends AppSheet {
  const AppMenuSheet(super.app);
}

/// An app's new title.
class AppRenameSheet extends AppSheet {
  const AppRenameSheet(super.app);
}

/// Whether to delete an app.
class AppDeleteSheet extends AppSheet {
  const AppDeleteSheet(super.app);
}

/// One log line and the app's data after it, with Restore unless it is the [latest] or comes
/// before [restorableFrom], the first line the log holds.
class LineSheet extends AppSheet {
  const LineSheet(
    super.app,
    this.line, {
    required this.latest,
    this.restorableFrom,
  });

  final LogLine line;
  final bool latest;

  /// The first line the log holds, when the server says; a line before it cannot be replayed.
  final int? restorableFrom;

  /// Whether the log no longer holds what came before [line], so it cannot be put back to.
  bool get compacted => restorableFrom != null && line.n < restorableFrom!;
}

/// One commit and its diff, with Revert when the server would revert it: as the commit's
/// `revertable` says, or from a server that does not say, unless it is the [first].
class CommitSheet extends AppSheet {
  const CommitSheet(super.app, this.commit, {required this.first});

  final AppCommit commit;
  final bool first;
}

/// [sheet] over the window.
class AppSheetView extends StatefulWidget {
  const AppSheetView(this.sheet, {super.key});

  final AppSheet sheet;

  @override
  State<AppSheetView> createState() => _AppSheetViewState();
}

class _AppSheetViewState extends State<AppSheetView> {
  /// Whether the sheet asks before its change, as Restore and Revert do.
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    final apps = AppScope.of(context).apps;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) apps.clearProblem();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sheet = widget.sheet;
    final title = scope.apps.appOf(sheet.app).title;
    return ListenableBuilder(
      listenable: scope.apps,
      builder: (context, _) => ModalSheet(
        title: switch (sheet) {
          AppMenuSheet() => title,
          AppRenameSheet() => 'Rename',
          AppDeleteSheet() => 'Delete app',
          LineSheet(:final latest) =>
            latest ? 'Current state' : 'State after this',
          CommitSheet(:final commit) => 'commit ${commit.short}',
        },
        autofocus: sheet is! AppRenameSheet,
        onClose: scope.shell.closePopup,
        // Each scrolls, as a short window leaves a sheet less room than it needs.
        child: SingleChildScrollView(
          child: switch (sheet) {
            AppMenuSheet() => _menu(context, title),
            AppRenameSheet() => _RenameForm(sheet.app, title: title),
            AppDeleteSheet() => _delete(context, title),
            LineSheet() => _line(context, sheet, title),
            CommitSheet() => _commit(context, sheet),
          },
        ),
      ),
    );
  }

  Widget _problem(BuildContext context) =>
      switch (AppScope.of(context).apps.changeProblem) {
        final problem? => AlertBox(
          AlertKind.bad,
          'That did not work',
          text: problem,
        ),
        null => const SizedBox.shrink(),
      };

  Widget _menu(BuildContext context, String title) {
    final shell = AppScope.of(context).shell;
    final app = widget.sheet.app;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        FieldCard([
          CardRow('Open', icon: 'grid', onTap: () => shell.openApp(app)),
          CardRow(
            'Files and history',
            icon: 'folder',
            onTap: () => shell.openApp(app, data: true),
          ),
          CardRow(
            'Rename',
            icon: 'pencil',
            onTap: () => shell.togglePopup(AppRenameSheet(app)),
          ),
        ]),
        FieldCard([
          CardRow(
            'Delete app',
            icon: 'trash',
            tone: RowTone.danger,
            onTap: () => shell.togglePopup(AppDeleteSheet(app)),
          ),
        ]),
      ],
    );
  }

  Widget _delete(BuildContext context, String title) {
    final scope = AppScope.of(context);
    final app = widget.sheet.app;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        _problem(context),
        SheetQuestion(
          'Delete $title? Its data and history go with it. Chats that show its '
          'card keep a picture that says it is gone.',
          onKeep: scope.shell.closePopup,
          onDelete: scope.apps.busy
              ? null
              : () async {
                  if (!await scope.apps.delete(app)) return;
                  scope.shell.closePopup();
                  if (scope.shell.app == app) scope.shell.closeApp();
                },
        ),
      ],
    );
  }

  Widget _line(BuildContext context, LineSheet sheet, String title) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final line = sheet.line;
    final now = DateTime.now();
    final said = [
      line.title,
      if (line.detail.isNotEmpty) line.detail,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            [
              '${sheet.latest ? 'After ' : ''}"$said"',
              if (line.t case final at?) whenShort(at, now),
              byText(line.by),
            ].join(' · '),
            style: Type.sans(16, color: t.ink, height: 1.45),
          ),
        ),
        MetaLine('log.jsonl', 'line ${line.n}'),
        CodeBox.text(prettyJson(line.json)),
        const MetaLine('State · derived from the log', ''),
        if (sheet.compacted)
          _note(
            context,
            'Not kept: the log was compacted at line ${sheet.restorableFrom}, '
            'so the state after this line can no longer be worked out, and '
            'the app cannot be put back to it.',
          )
        else
          FutureBuilder(
            future: scope.apps.state(sheet.app, line.n),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final error = snapshot.error;
                return AlertBox(
                  AlertKind.warn,
                  'Could not read the state',
                  text: error is ApiException ? error.message : '$error',
                );
              }
              final state = snapshot.data;
              return state == null
                  ? Text('Reading…', style: Type.sans(14, color: t.muted))
                  : CodeBox.text(prettyJson(state.data));
            },
          ),
        _problem(context),
        if (!sheet.latest && !sheet.compacted)
          if (_asking) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Put $title back to this? It is added to the log as a new '
                'line, and what came after stays in it.',
                style: Type.sans(15.5, color: t.ink, height: 1.5),
              ),
            ),
            ActionRow(even: true, [
              AppButton(
                'Keep',
                onPressed: () => setState(() => _asking = false),
              ),
              AppButton(
                'Restore',
                primary: true,
                onPressed: scope.apps.busy
                    ? null
                    : () async {
                        final done = await scope.apps.restore(
                          sheet.app,
                          line.n,
                        );
                        if (done) scope.shell.closePopup();
                      },
              ),
            ]),
          ] else
            AppButton(
              'Put the app back to this',
              onPressed: () => setState(() => _asking = true),
            ),
      ],
    );
  }

  Widget _commit(BuildContext context, CommitSheet sheet) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final commit = sheet.commit;
    final revertable = commit.canRevert(first: sheet.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            commit.title,
            style: Type.sans(
              16,
              weight: FontWeight.w600,
              color: t.ink,
              height: 1.45,
            ),
          ),
        ),
        if (commit.details case final details when details.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              details,
              style: Type.sans(15, color: t.ink2, height: 1.5),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            commitAbout(commit, DateTime.now()),
            style: Type.note(t.muted),
          ),
        ),
        FutureBuilder(
          future: scope.apps.diff(sheet.app, commit.commit),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              final error = snapshot.error;
              return AlertBox(
                AlertKind.warn,
                'Could not read the diff',
                text: error is ApiException ? error.message : '$error',
              );
            }
            final diff = snapshot.data;
            if (diff == null) {
              return Text('Reading…', style: Type.sans(14, color: t.muted));
            }
            final files = diff.files;
            if (files == null) return CodeBox(diffLines(diffBody(diff.diff)));
            if (files.isEmpty) return _note(context, 'No file changed.');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [for (final file in files) FileDiffView(file)],
            );
          },
        ),
        _problem(context),
        if (!revertable && commit.revertable == false)
          _note(
            context,
            sheet.first
                ? 'Not revertable: it made the app, so there is nothing '
                      'before it.'
                : commit.files.contains('log.jsonl')
                ? 'Not revertable: it holds the log. Put the app back to a '
                      'line of the log instead.'
                : 'Not revertable: the apps server refuses it.',
          ),
        if (revertable)
          if (_asking) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Revert this commit? The undoing is a new commit, and the '
                'app\'s data stays as it is.',
                style: Type.sans(15.5, color: t.ink, height: 1.5),
              ),
            ),
            ActionRow(even: true, [
              AppButton(
                'Keep',
                onPressed: () => setState(() => _asking = false),
              ),
              AppButton(
                'Revert',
                danger: true,
                onPressed: scope.apps.busy
                    ? null
                    : () async {
                        final done = await scope.apps.revert(
                          sheet.app,
                          commit.commit,
                        );
                        if (done) scope.shell.closePopup();
                      },
              ),
            ]),
          ] else
            AppButton(
              'Revert this commit',
              onPressed: () => setState(() => _asking = true),
            ),
      ],
    );
  }
}

/// [text] as a muted note in a sheet.
Widget _note(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 8),
  child: Text(text, style: Type.note(Tokens.of(context).muted)),
);

/// The app's title in a field, then what renaming changes, then Save.
class _RenameForm extends StatefulWidget {
  const _RenameForm(this.app, {required this.title});

  final AppRef app;
  final String title;

  @override
  State<_RenameForm> createState() => _RenameFormState();
}

class _RenameFormState extends State<_RenameForm> {
  late final _name = TextEditingController(text: widget.title)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.title.length,
    );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final scope = AppScope.of(context);
    if (_name.text.trim() == widget.title) return scope.shell.closePopup();
    final done = await scope.apps.rename(widget.app, _name.text);
    if (done && mounted) scope.shell.togglePopup(AppMenuSheet(widget.app));
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        NamedControl(
          'Name',
          quiet: true,
          labelled: true,
          AppField(
            controller: _name,
            label: 'Name',
            autofocus: true,
            onSubmitted: (_) => unawaited(_save()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Changes the title in app.json, as a commit you can revert. The '
            'folder keeps its name, apps/${widget.app.name}.',
            style: Type.note(t.muted),
          ),
        ),
        _problemOf(context),
        AppButton(
          'Save',
          primary: true,
          onPressed: scope.apps.busy ? null : () => unawaited(_save()),
        ),
      ],
    );
  }

  Widget _problemOf(BuildContext context) =>
      switch (AppScope.of(context).apps.changeProblem) {
        final problem? => AlertBox(
          AlertKind.bad,
          'That did not work',
          text: problem,
        ),
        null => const SizedBox.shrink(),
      };
}

/// Opens [app]'s menu, as its row's More does.
void openAppMenu(ShellController shell, AppRef app) =>
    shell.togglePopup(AppMenuSheet(app));
