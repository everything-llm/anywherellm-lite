import 'dart:convert';
import 'dart:typed_data';

import 'package:anywherellm/core/apps.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/push.dart';
import 'package:anywherellm/core/system_files.dart';

import 'fake_companion.dart';
import 'pixels.dart';

/// An [AppsApi] for widget tests that keeps its apps in memory. It is absent, as beside a stock
/// AnythingLLM, until [present] is set. Put an error in [errors] under a method's name to make
/// it fail. Every call is recorded in [calls] as `name` or `name:arg`.
///
/// Each app's `line`, `restorable_from` and `version` follow its folder: its log's newest and
/// oldest lines and its newest commit. With [older] it is an apps server from before those
/// fields: no `version`, `restorable_from`, `revertable`, `subject`, `body` or diff `files`,
/// no `ETag` on a card, neither `GET /apps/<workspace>/<name>` nor `GET .../log`, and no
/// System files in its `/health`.
///
/// System files are [system]: each file's text by its path, null for a file that is not text,
/// its folders made from the paths.
class FakeApps with FakeCompanion implements AppsApi {
  FakeApps({this.present = false, this.older = false});

  @override
  bool present;

  /// Whether it is an apps server from before the paged log, versions and split diffs.
  bool older;

  /// The most lines a page of the log holds, whatever the client asks: 500, as the server's.
  int pageMax = 500;

  @override
  Companion get companion => appsCompanion;

  /// Where [pages] says the working pages are, while [present].
  Uri pagesAt = Uri.parse('https://h:8465');

  @override
  Future<Uri?> pages() async => present ? pagesAt : null;

  /// An older apps server names no features.
  @override
  Set<String> get served =>
      older ? const {} : const {AppsFeature.systemFiles, AppsFeature.push};

  /// Each workspace's apps, by slug.
  final Map<String, List<ServerApp>> spaces = {};

  /// Each app's files, by path, with their text.
  final Map<AppRef, Map<String, String>> folders = {};

  /// Each app's commits, newest first.
  final Map<AppRef, List<AppCommit>> commits = {};

  /// Each commit's diff, by hash.
  final Map<String, String> diffs = {};

  /// What [card] answers, by the address asked.
  final Map<Uri, Uint8List> cards = {};

  /// Every card address asked, in order.
  final List<Uri> cardAsks = [];

  /// Every card address answered `304 Not Modified`, in order.
  final List<Uri> cardsUnchanged = [];

  /// System files: each file's text by its path, null for one that is not text.
  final Map<String, String?> system = {
    'apps/home/groceries/app.json': '{"title": "Groceries", "kind": "list"}',
    'skill/handler.js': 'module.exports.runtime = {}',
    'skill/lib/hostrpc.js': '// the socket',
    'runner/DEPLOYED': 'commit 4232f38',
    'runner/anythingllm_apps_v2/assets/fonts/Sans.ttf': null,
    'settings/apps.env': 'ANYTHINGLLM_API_KEY=(set)',
  };

  void _fail(String method) {
    if (errors[method] case final error?) throw error;
  }

  @override
  Future<List<ServerApp>> apps(String workspace) async {
    calls.add('apps:$workspace');
    _fail('apps');
    return [for (final app in spaces[workspace] ?? <ServerApp>[]) _now(app)];
  }

  @override
  Future<ServerApp?> app(AppRef app) async {
    calls.add('app:${app.name}');
    if (older) return null;
    _fail('app');
    final found = spaces[app.workspace]?.where((a) => a.ref == app).firstOrNull;
    if (found == null) throw const ApiException('No such app.', status: 404);
    return _now(found);
  }

  /// [app] as the server would list it now, its line, first line and version read from its
  /// folder.
  ServerApp _now(ServerApp app) {
    final log = folders[app.ref]?['log.jsonl'];
    final lines = log == null ? null : logLinesOf(log);
    final line = lines?.firstOrNull?.n ?? app.line;
    final head = commits[app.ref]?.firstOrNull?.commit ?? '000000000000';
    final readable = app.error == null && !older;
    return ServerApp(
      ref: app.ref,
      title: app.title,
      kind: app.kind,
      summary: app.summary,
      modified: app.modified,
      line: line,
      restorableFrom: readable ? lines?.lastOrNull?.n ?? 1 : null,
      version: readable
          ? '$line-${head.substring(0, head.length < 12 ? head.length : 12)}'
          : null,
      page: app.page,
      card: app.card,
      error: app.error,
    );
  }

  @override
  Future<LogPage?> log(AppRef app, {int? before, int limit = 100}) async {
    calls.add('log:${before ?? 'newest'}');
    if (older) return null;
    _fail('log');
    final log =
        folders[app]?['log.jsonl'] ??
        (throw const ApiException('No such app.', status: 404));
    final all = logLinesOf(log);
    final below = [
      for (final line in all)
        if (before == null || line.n < before) line,
    ];
    final size = limit < pageMax ? limit : pageMax;
    return LogPage(
      lines: below.take(size).toList(),
      first: all.lastOrNull?.n,
      last: all.firstOrNull?.n,
      more: below.length > size,
    );
  }

  @override
  Future<List<AppFile>> files(AppRef app) async {
    calls.add('files:${app.name}');
    _fail('files');
    final modified = spaces[app.workspace]
        ?.where((a) => a.ref == app)
        .firstOrNull
        ?.modified;
    return [
      for (final MapEntry(:key, :value) in (folders[app] ?? {}).entries)
        AppFile(key, size: utf8.encode(value).length, modified: modified),
    ];
  }

  @override
  Future<String> file(AppRef app, String path) async {
    calls.add('file:$path');
    _fail('file');
    return folders[app]?[path] ??
        (throw const ApiException('No such file.', status: 404));
  }

  /// The data after line [line], replayed from the log's patches.
  @override
  Future<AppState> state(AppRef app, {int? line}) async {
    calls.add('state:${line ?? 'now'}');
    _fail('state');
    final lines = logLinesOf(folders[app]?['log.jsonl'] ?? '').reversed;
    final first = lines.firstOrNull?.n;
    if (line != null && first != null && line < first) {
      throw const ApiException('That line was compacted.', status: 404);
    }
    Object? data;
    var upto = 0;
    for (final entry in lines) {
      if (line != null && entry.n > line) break;
      upto = entry.n;
      for (final op in entry.json['patch'] as List? ?? const []) {
        data = _apply(data, op as Map);
      }
    }
    return AppState(upto, data, restorableFrom: older ? null : first);
  }

  /// [data] with the JSON Patch operation [op] applied: `add`, `replace` and `remove`, enough
  /// for the fake's logs. A `test` changes nothing.
  static Object? _apply(Object? data, Map<dynamic, dynamic> op) {
    final path = op['path'] as String;
    if (path.isEmpty) return op['op'] == 'remove' ? null : _copy(op['value']);
    final keys = path.substring(1).split('/');
    final root = _copy(data);
    Object? parent = root;
    for (final key in keys.take(keys.length - 1)) {
      parent = parent is List ? parent[int.parse(key)] : (parent as Map)[key];
    }
    final last = keys.last;
    switch ((op['op'], parent)) {
      case ('test', _):
        break;
      case ('remove', final List list):
        list.removeAt(int.parse(last));
      case ('remove', final Map map):
        map.remove(last);
      case ('add', final List list):
        last == '-'
            ? list.add(_copy(op['value']))
            : list.insert(int.parse(last), _copy(op['value']));
      case (_, final List list):
        list[int.parse(last)] = _copy(op['value']);
      case (_, final Map map):
        map[last] = _copy(op['value']);
    }
    return root;
  }

  static Object? _copy(Object? value) => jsonDecode(jsonEncode(value));

  @override
  Future<List<AppCommit>> history(AppRef app) async {
    calls.add('history:${app.name}');
    _fail('history');
    return [
      for (final commit in commits[app] ?? <AppCommit>[])
        older
            ? AppCommit(
                commit: commit.commit,
                t: commit.t,
                by: commit.by,
                chat: commit.chat,
                message: commit.message,
                files: commit.files,
              )
            : commit,
    ];
  }

  @override
  Future<AppDiff> diff(AppRef app, String commit) async {
    calls.add('diff:$commit');
    _fail('diff');
    final show = diffs[commit] ?? '';
    return AppDiff(show, files: older ? null : _filesOf(show));
  }

  /// The files of [show], the text of `git show`, as the server splits them: each one's path,
  /// what was done to it, and its hunks from its first `@@` line.
  static List<FileDiff> _filesOf(String show) {
    final files = <FileDiff>[];
    for (final part in show.split('\ndiff --git ').skip(1)) {
      final lines = const LineSplitter().convert(part);
      final path = lines.first.split(' b/').last;
      final status = lines.any((l) => l.startsWith('new file'))
          ? FileChange.added
          : lines.any((l) => l.startsWith('deleted file'))
          ? FileChange.deleted
          : FileChange.modified;
      final hunks = lines.indexWhere((l) => l.startsWith('@@'));
      files.add(
        FileDiff(
          path,
          status,
          hunks < 0 ? '' : '${lines.skip(hunks).join('\n')}\n',
        ),
      );
    }
    return files;
  }

  @override
  Future<int> restore(AppRef app, int line) async {
    calls.add('restore:$line');
    _fail('restore');
    final folder = folders[app]!;
    final log = folder['log.jsonl'] ?? '';
    final state = await this.state(app, line: line);
    final n = (logLinesOf(log).firstOrNull?.n ?? 0) + 1;
    folder['log.jsonl'] =
        '$log${jsonEncode({
          'n': n,
          't': '2026-10-12T09:00:00Z',
          'by': 'you',
          'ev': 'restore',
          'to': line,
          'patch': [
            {'op': 'replace', 'path': '', 'value': state.data},
          ],
        })}\n';
    return n;
  }

  @override
  Future<String> revert(AppRef app, String commit) async {
    calls.add('revert:$commit');
    _fail('revert');
    final message =
        'Revert "${commits[app]!.firstWhere((c) => c.commit == commit).title}"';
    final made = AppCommit(
      commit: 'ffffffff${commits[app]!.length}',
      by: 'you',
      message: message,
      subject: message,
      body: '',
      files: const ['app.json'],
      revertable: true,
    );
    commits[app]!.insert(0, made);
    return made.commit;
  }

  @override
  Future<void> rename(AppRef app, String title) async {
    calls.add('rename:$title');
    _fail('rename');
    final list = spaces[app.workspace]!;
    final i = list.indexWhere((a) => a.ref == app);
    final was = list[i];
    commits[app]?.insert(
      0,
      AppCommit(
        commit: 'eeeeeeee${commits[app]!.length}',
        by: 'you',
        message: 'Rename to $title',
        subject: 'Rename to $title',
        body: '',
        files: const ['app.json'],
        revertable: true,
      ),
    );
    list[i] = ServerApp(
      ref: was.ref,
      title: title,
      kind: was.kind,
      summary: was.summary,
      modified: was.modified,
      line: was.line,
      page: was.page,
      card: was.card,
    );
  }

  @override
  Future<void> delete(AppRef app) async {
    calls.add('delete:${app.name}');
    _fail('delete');
    spaces[app.workspace]?.removeWhere((a) => a.ref == app);
    folders.remove(app);
  }

  /// The card at [url], with its `ETag` from its app's version and theme unless [older]; a
  /// [last] whose tag still matches is answered as `304 Not Modified`.
  @override
  Future<CardPicture> card(Uri url, {CardPicture? last}) async {
    cardAsks.add(url);
    _fail('card');
    final tag = older ? null : _tagOf(url);
    if (tag != null && last != null && last.etag == tag) {
      cardsUnchanged.add(url);
      return last;
    }
    return CardPicture(cards[url] ?? pixel, etag: tag);
  }

  /// The `ETag` of the card at [url]: `"<version>-<theme>"`, or `"gone-<theme>"` for an app
  /// that is not there.
  String? _tagOf(Uri url) {
    final parts = url.pathSegments;
    if (parts.length != 3 || parts[0] != 'cards') return null;
    final ref = AppRef(parts[1], parts[2].replaceAll('.png', ''));
    final theme = url.queryParameters['theme'] == 'light' ? 'light' : 'dark';
    final app = spaces[ref.workspace]?.where((a) => a.ref == ref).firstOrNull;
    final version = app == null ? 'gone' : _now(app).version;
    return version == null ? null : '"$version-$theme"';
  }

  /// The devices [subscribePush] keeps, by endpoint.
  final pushDevices = <String, PushSubscription>{};

  @override
  Future<String> pushKey() async {
    calls.add('pushKey');
    _fail('pushKey');
    return 'BAppsKey';
  }

  @override
  Future<void> subscribePush(PushSubscription subscription) async {
    calls.add('subscribePush');
    _fail('subscribePush');
    pushDevices[subscription.endpoint] = subscription;
  }

  @override
  Future<void> unsubscribePush(String endpoint) async {
    calls.add('unsubscribePush');
    _fail('unsubscribePush');
    pushDevices.remove(endpoint);
  }

  @override
  Future<List<SystemEntry>> systemFolder(String path) async {
    calls.add('systemFolder:$path');
    _fail('systemFolder');
    final prefix = path.isEmpty ? '' : '$path/';
    final folders = <String>{};
    final files = <String>[];
    for (final file in system.keys.where((f) => f.startsWith(prefix))) {
      final rest = file.substring(prefix.length).split('/');
      rest.length == 1 ? files.add(rest.single) : folders.add(rest.first);
    }
    if (path.isNotEmpty && folders.isEmpty && files.isEmpty) {
      throw ApiException("No folder '$path'.", status: 404);
    }
    int count(String folder) => {
      for (final file in system.keys.where(
        (f) => f.startsWith('$prefix$folder/'),
      ))
        file.substring('$prefix$folder/'.length).split('/').first,
    }.length;
    return [
      for (final folder in folders.toList()..sort())
        SystemEntry(folder, folder: true, count: count(folder)),
      for (final file in files..sort())
        SystemEntry(
          file,
          folder: false,
          size: utf8.encode(system['$prefix$file'] ?? 'xx').length,
        ),
    ];
  }

  @override
  Future<String?> systemFile(String path) async {
    calls.add('systemFile:$path');
    _fail('systemFile');
    if (!system.containsKey(path)) {
      throw ApiException("No file '$path'.", status: 404);
    }
    return system[path];
  }
}

/// The host the sample apps live on, as [sampleConnection]'s.
const _host = 'h';

/// An apps server holding Groceries, a list in workspace [workspace], with its folder, log and
/// git history.
FakeApps groceriesServer({String workspace = 'q3'}) {
  final ref = AppRef(workspace, 'groceries');
  final apps = FakeApps(present: true);
  apps.spaces[workspace] = [
    ServerApp(
      ref: ref,
      title: 'Groceries',
      kind: 'list',
      summary: '1 of 2 left',
      modified: DateTime.utc(2026, 10, 12, 8, 14),
      line: 3,
      page: Uri.parse('https://$_host:8465/$workspace/groceries/'),
      card: Uri.parse('https://$_host:8466/cards/$workspace/groceries.png'),
    ),
  ];
  String line(int n, String by, String ev, Object? data, [Map? fields]) =>
      jsonEncode({
        'n': n,
        't': '2026-10-12T08:1$n:03Z',
        'by': by,
        'ev': ev,
        ...?fields,
        'patch': [
          {'op': 'replace', 'path': '', 'value': data},
        ],
      });
  apps.folders[ref] = {
    'app.json': jsonEncode({
      'title': 'Groceries',
      'kind': 'list',
      'about': 'A list of things to get.',
      'rules': ['Tick an item rather than removing it.'],
    }),
    'log.jsonl':
        '${[
          line(1, 'agent', 'made', {
            'items': [
              {'text': 'Milk', 'done': false},
            ],
          }),
          line(2, 'you', 'add', {
            'items': [
              {'text': 'Milk', 'done': false},
              {'text': 'Eggs', 'done': false},
            ],
          }, {'text': 'Eggs'}),
          line(3, 'you', 'tick', {
            'items': [
              {'text': 'Milk', 'done': true},
              {'text': 'Eggs', 'done': false},
            ],
          }, {'text': 'Milk'}),
        ].join('\n')}\n',
    'page.html': '<script src="app.js"></script>\n<ul id="items"></ul>',
  };
  apps.commits[ref] = [
    AppCommit(
      commit: '5f6c11f0a1b2c3d4e5f60718293a4b5c6d7e8f90',
      t: DateTime.utc(2026, 10, 12, 8, 20),
      by: 'agent',
      chat: '8f11958e-7dec-446e-81bd-b46e6d2b3eb0',
      message: 'Ticks move to the bottom\n\nA ticked item sinks below the ones left.',
      subject: 'Ticks move to the bottom',
      body: 'A ticked item sinks below the ones left.',
      files: const ['page.html'],
      revertable: true,
    ),
    AppCommit(
      commit: '1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d',
      t: DateTime.utc(2026, 10, 12, 8, 0),
      by: 'agent',
      message: 'Make Groceries',
      subject: 'Make Groceries',
      body: '',
      files: const ['app.json', 'page.html'],
      revertable: false,
    ),
  ];
  apps.diffs['5f6c11f0a1b2c3d4e5f60718293a4b5c6d7e8f90'] =
      'commit 5f6c11f0a1b2c3d4e5f60718293a4b5c6d7e8f90\n'
      'Author: agent <agent@apps>\n\n'
      '    Ticks move to the bottom\n\n'
      'diff --git a/page.html b/page.html\n'
      '--- a/page.html\n'
      '+++ b/page.html\n'
      '@@ -1,2 +1,3 @@\n'
      ' <script src="app.js"></script>\n'
      '-<ul id="items"></ul>\n'
      '+<ul id="items" class="sorted"></ul>\n';
  return apps;
}
