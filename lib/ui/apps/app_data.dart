import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/apps.dart';
import '../../core/copy.dart';
import '../../core/ports.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../settings/rows.dart';
import '../state/log_pages.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/phone_page.dart';
import '../widgets/tappable.dart';
import 'app_sheets.dart';
import 'json_view.dart';

/// One page of [app]'s data, as [page] says: its folder, a file, its log or its git history.
class AppDataPage extends StatelessWidget {
  const AppDataPage(this.page, {super.key, required this.app});

  final AppPage page;
  final ServerApp app;

  @override
  Widget build(BuildContext context) => switch (page) {
    AppFolder() => _Folder(app),
    AppFileOf(:final path) when path == 'log.jsonl' => _Log(app),
    AppFileOf(:final path) => _File(app, path),
    AppLog() => _Log(app),
    AppGit() => _Git(app),
  };
}

/// What [future] gives, drawn by [done]; while it is read a muted line, and when it fails the
/// failure.
class _Read<T> extends StatelessWidget {
  const _Read(this.future, {required this.done});

  final Future<T> future;
  final Widget Function(BuildContext context, T value) done;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        final error = snapshot.error;
        return Padding(
          padding: Sizes.pagePadding,
          child: AlertBox(
            AlertKind.warn,
            'Could not read this',
            text: error is ApiException ? error.message : '$error',
          ),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return Padding(
          padding: Sizes.pagePadding,
          child: Text(
            'Reading…',
            style: Type.sans(14, color: Tokens.of(context).muted),
          ),
        );
      }
      return done(context, snapshot.data as T);
    },
  );
}

/// A header's title in the mono face, as a file's name is.
Widget _monoTitle(BuildContext context, String text) => Semantics(
  header: true,
  child: Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.center,
    style: Type.mono(
      17,
      weight: FontWeight.w600,
      color: Tokens.of(context).ink,
    ),
  ),
);

/// The round button at a header's end that shows a file raw, filled in the accent while on.
Widget _rawButton(BuildContext context, bool raw, VoidCallback onTap) {
  final t = Tokens.of(context);
  return Tappable(
    label: 'Show the raw file',
    selected: raw,
    touchTarget: true,
    onTap: onTap,
    child: Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: raw ? t.accent : t.hover,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: AppIcon(
          'code',
          size: IconSize.normal,
          color: raw ? t.onaccent : t.ink,
        ),
      ),
    ),
  );
}

/// A row of the folder: [icon], [name] in the mono face over [about], and a chevron.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.icon,
    required this.name,
    required this.about,
    required this.onTap,
  });

  final String icon;
  final String name;
  final String about;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: '$name, $about',
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: Sizes.cardRow),
        padding: const EdgeInsets.symmetric(
          horizontal: FieldCard.inset,
          vertical: 10,
        ),
        child: Row(
          spacing: 14,
          children: [
            AppIcon(icon, size: IconSize.medium, color: t.ink),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: [
                  Text(
                    name,
                    style: Type.mono(15, weight: FontWeight.w600, color: t.ink),
                  ),
                  Text(
                    about,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.sans(13, color: t.muted),
                  ),
                ],
              ),
            ),
            AppIcon('chevron', size: IconSize.xs, color: t.muted),
          ],
        ),
      ),
    );
  }
}

/// The app's folder: each of its files with its size and when it last changed, then its git
/// history, then what is left out and why.
class _Folder extends StatelessWidget {
  const _Folder(this.app);

  final ServerApp app;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final apps = scope.apps;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhonePageHeader(
          title: app.title,
          back: 'Back to ${app.title}',
          onBack: shell.appBack,
        ),
        Expanded(
          child: _Read(
            apps.files(app.ref),
            done: (context, files) => ListView(
              padding: Sizes.pagePadding,
              children: [
                MetaLine(
                  'apps/${app.ref.name}/',
                  plural(files.length, 'file', 'files'),
                ),
                FieldCard([
                  for (final file in files)
                    _EntryRow(
                      icon: 'doc',
                      name: file.path,
                      about: [
                        bytesText(file.size),
                        if (file.modified case final at?) whenShort(at, now),
                      ].join(' · '),
                      onTap: () => shell.showAppPage(
                        file.path == 'log.jsonl'
                            ? const AppLog()
                            : AppFileOf(file.path),
                      ),
                    ),
                ]),
                const SizedBox(height: 16),
                FutureBuilder(
                  future: apps.commits(app.ref),
                  builder: (context, snapshot) => FieldCard([
                    _EntryRow(
                      icon: 'clock',
                      name: '.git',
                      about: [
                        'History of app.json and page.html',
                        if (snapshot.data case final commits?)
                          plural(commits.length, 'commit', 'commits'),
                      ].join(' · '),
                      onTap: () => shell.showAppPage(const AppGit()),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FieldCard.inset,
                  ),
                  child: Text(
                    'Not listed: .cache/, which the apps server rebuilds. The '
                    'page\'s write token is kept by the server, outside this '
                    'folder, and never shown.',
                    style: Type.note(Tokens.of(context).muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One file of the app's folder, raw with its lines numbered; a JSON file is read as JSON
/// unless shown raw.
class _File extends StatefulWidget {
  const _File(this.app, this.path);

  final ServerApp app;
  final String path;

  @override
  State<_File> createState() => _FileState();
}

class _FileState extends State<_File> {
  bool _raw = false;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final json = widget.path.endsWith('.json');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhonePageHeader(
          back: 'Back to the folder',
          onBack: scope.shell.appBack,
          heading: _monoTitle(context, widget.path),
          action: json
              ? _rawButton(context, _raw, () => setState(() => _raw = !_raw))
              : null,
        ),
        Expanded(
          child: _Read(
            scope.apps.text(widget.app.ref, widget.path),
            done: (context, text) {
              Object? parsed;
              if (json && !_raw) {
                try {
                  parsed = jsonDecode(text);
                } on FormatException {
                  parsed = null;
                }
              }
              final lines = const LineSplitter().convert(text).length;
              return ListView(
                padding: Sizes.pagePadding,
                children: [
                  MetaLine(
                    'apps/${widget.app.ref.name}/${widget.path}',
                    '${plural(lines, 'line', 'lines')} · '
                        '${bytesText(utf8.encode(text).length)}',
                  ),
                  if (parsed != null)
                    JsonCard(JsonView(parsed))
                  else
                    NumberedText(text),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The app's log read as its history: each line newest first under its day, with its event,
/// its fields, who wrote it and when, a page at a time, an older page read as the list nears
/// its end or on Show older. Tapped, a line shows the data after it. Shown raw, the file's
/// lines numbered.
class _Log extends StatefulWidget {
  const _Log(this.app);

  final ServerApp app;

  @override
  State<_Log> createState() => _LogState();
}

class _LogState extends State<_Log> {
  bool _raw = false;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final ref = widget.app.ref;
    final pages = scope.apps.log(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhonePageHeader(
          back: 'Back to the folder',
          onBack: scope.shell.appBack,
          heading: _monoTitle(context, 'log.jsonl'),
          action: _rawButton(context, _raw, () => setState(() => _raw = !_raw)),
        ),
        Expanded(
          child: _raw
              ? _Read(
                  scope.apps.text(ref, 'log.jsonl'),
                  done: (context, text) => ListView(
                    padding: Sizes.pagePadding,
                    children: [
                      MetaLine(
                        'apps/${ref.name}/log.jsonl',
                        bytesText(utf8.encode(text).length),
                      ),
                      NumberedText(text),
                    ],
                  ),
                )
              : ListenableBuilder(
                  listenable: pages,
                  builder: (context, _) => _history(context, pages),
                ),
        ),
        if (!_raw)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: t.bg,
              border: Border(top: BorderSide(color: t.line2)),
            ),
            child: ListenableBuilder(
              listenable: pages,
              builder: (context, _) {
                final newest = pages.lines.firstOrNull;
                return _NowButton(
                  newest,
                  onTap: newest == null
                      ? null
                      : () => scope.shell.togglePopup(
                          LineSheet(ref, newest, latest: true),
                        ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// The lines read so far, or why the first page could not be read.
  Widget _history(BuildContext context, LogPages pages) {
    final t = Tokens.of(context);
    if (!pages.loaded) {
      return Padding(
        padding: Sizes.pagePadding,
        child: Text('Reading…', style: Type.sans(14, color: t.muted)),
      );
    }
    if (pages.lines.isEmpty && pages.problem != null) {
      return Padding(
        padding: Sizes.pagePadding,
        child: AlertBox(
          AlertKind.warn,
          'Could not read this',
          text: pages.problem,
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (note) {
        if (note.metrics.extentAfter < 400 &&
            pages.more &&
            !pages.reading &&
            pages.problem == null) {
          // A read tells its listeners at once, so it waits for the scroll to be handled.
          scheduleMicrotask(pages.older);
        }
        return false;
      },
      child: _picker(context, pages),
    );
  }

  Widget _picker(BuildContext context, LogPages pages) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final now = DateTime.now();
    final lines = pages.lines;
    final from = pages.first ?? widget.app.restorableFrom;
    final children = <Widget>[];
    String? day;
    for (final (i, line) in lines.indexed) {
      final today = line.t == null ? 'No time' : dayText(line.t!, now);
      if (today != day) {
        day = today;
        children.add(CardHeading(today, top: children.isEmpty ? 4 : 16));
      }
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _LineCard(
            line,
            now: now,
            onTap: () => scope.shell.togglePopup(
              LineSheet(
                widget.app.ref,
                line,
                latest: i == 0,
                restorableFrom: from,
              ),
            ),
          ),
        ),
      );
    }
    return ListView(
      padding: Sizes.pagePadding,
      children: [
        if (lines.isEmpty)
          const FieldCard([CardNote('The log is empty.')])
        else ...[
          ...children,
          if (pages.problem case final problem?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AlertBox(
                AlertKind.warn,
                'Could not read older lines',
                text: problem,
              ),
            ),
          if (pages.more)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ActionRow(even: true, [
                AppButton(
                  pages.reading ? 'Reading…' : 'Show older',
                  onPressed: pages.reading
                      ? null
                      : () => unawaited(pages.older()),
                ),
              ]),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FieldCard.inset,
                12,
                FieldCard.inset,
                0,
              ),
              child: Text(
                from != null && from > 1
                    ? 'The log starts at line $from, where it was compacted. '
                          'The app cannot be put back to a line before it.'
                    : 'The beginning',
                textAlign: TextAlign.center,
                style: Type.sans(14, color: t.muted),
              ),
            ),
        ],
      ],
    );
  }
}

/// One line of the log as a card: a dot for who wrote it, its event and fields, when, and a
/// badge when the agent, a device or the server wrote it.
class _LineCard extends StatelessWidget {
  const _LineCard(this.line, {required this.now, required this.onTap});

  final LogLine line;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final you = line.by == 'you';
    final detail = line.detail;
    final when = line.t == null ? '' : clockText(line.t!.toLocal());
    return Tappable(
      label: [
        'Line ${line.n}',
        line.title,
        if (detail.isNotEmpty) detail,
        byText(line.by),
        if (line.t != null) whenShort(line.t!, now),
      ].join(', '),
      radius: BorderRadius.circular(Sizes.notice),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.circular(Sizes.notice),
          border: Border.all(color: t.line2),
        ),
        child: Row(
          spacing: 12,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: you ? t.okbg : t.accentbg,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: AppIcon(
                  you ? 'check' : 'grid',
                  size: IconSize.tiny,
                  color: you ? t.okfg : t.accent,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    line.title,
                    style: Type.sans(
                      15.5,
                      weight: FontWeight.w500,
                      color: t.ink,
                    ),
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Type.sans(13, color: t.muted),
                    ),
                ],
              ),
            ),
            if (!you) _Badge(byText(line.by)),
            Text(when, style: Type.sans(13, color: t.muted)),
          ],
        ),
      ),
    );
  }
}

/// A small pill naming who wrote a line, when it was not the person.
class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: t.accentbg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: Type.sans(11.5, weight: FontWeight.w600, color: t.accent),
      ),
    );
  }
}

/// The button under the log that shows the app's data now, after its newest line.
class _NowButton extends StatelessWidget {
  const _NowButton(this.newest, {required this.onTap});

  final LogLine? newest;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final after = newest == null ? 'Now' : 'Now · after line ${newest!.n}';
    return Tappable(
      label: 'Current state, $after',
      radius: BorderRadius.circular(Sizes.notice),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.fromLTRB(16, 8, 14, 8),
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.circular(Sizes.notice),
          border: Border.all(color: t.accent),
        ),
        child: Row(
          spacing: 12,
          children: [
            AppIcon('doc', size: IconSize.medium, color: t.ink),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(after, style: Type.sans(13, color: t.muted)),
                  Text(
                    'Current state',
                    style: Type.sans(
                      15.5,
                      weight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                ],
              ),
            ),
            AppIcon('chevron', size: IconSize.xs, color: t.muted),
          ],
        ),
      ),
    );
  }
}

/// The folder's commits, newest first: each one's short hash, message, who made it, when and
/// in which chat. Tapped, one shows its diff.
class _Git extends StatelessWidget {
  const _Git(this.app);

  final ServerApp app;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhonePageHeader(
          back: 'Back to the folder',
          onBack: scope.shell.appBack,
          heading: _monoTitle(context, 'git log'),
        ),
        Expanded(
          child: _Read(
            scope.apps.commits(app.ref),
            done: (context, commits) => ListView(
              padding: Sizes.pagePadding,
              children: [
                MetaLine(
                  'apps/${app.ref.name}/.git',
                  plural(commits.length, 'commit', 'commits'),
                ),
                FieldCard([
                  for (final (i, commit) in commits.indexed)
                    Tappable(
                      label: '${commit.title}, ${commit.short}',
                      onTap: () => scope.shell.togglePopup(
                        CommitSheet(
                          app.ref,
                          commit,
                          first: i == commits.length - 1,
                        ),
                      ),
                      child: Container(
                        constraints: const BoxConstraints(
                          minHeight: Sizes.cardRow,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: FieldCard.inset,
                          vertical: 10,
                        ),
                        child: Row(
                          spacing: 12,
                          children: [
                            Text(
                              commit.short,
                              style: Type.mono(13, color: t.accent),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                spacing: 2,
                                children: [
                                  Text(
                                    commit.title,
                                    style: Type.sans(
                                      15,
                                      weight: FontWeight.w600,
                                      color: t.ink,
                                      height: 1.35,
                                    ),
                                  ),
                                  if (commit.details case final details
                                      when details.isNotEmpty)
                                    Text(
                                      details,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Type.sans(
                                        13.5,
                                        color: t.ink2,
                                        height: 1.4,
                                      ),
                                    ),
                                  Text(
                                    commitAbout(commit, now),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Type.sans(13, color: t.muted),
                                  ),
                                ],
                              ),
                            ),
                            AppIcon(
                              'chevron',
                              size: IconSize.xs,
                              color: t.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Who made [commit], when and in which chat: `agent · Today 07:40 · 8f11958e`.
String commitAbout(AppCommit commit, DateTime now) => [
  byText(commit.by).toLowerCase(),
  if (commit.t case final at?) whenShort(at, now),
  if (commit.chat case final chat?)
    chat.length > 8 ? chat.substring(0, 8) : chat,
].join(' · ');
