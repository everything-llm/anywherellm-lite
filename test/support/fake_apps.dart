import 'dart:convert';
import 'dart:typed_data';

import 'package:anywherellm/core/apps.dart';
import 'package:anywherellm/core/ports.dart';

import 'pixels.dart';

/// An [AppsApi] for widget tests that keeps its apps in memory. It is absent, as beside a stock
/// AnythingLLM, until [present] is set. Put an error in [errors] under a method's name to make
/// it fail. Every call is recorded in [calls] as `name` or `name:arg`.
class FakeApps implements AppsApi {
  FakeApps({this.present = false});

  /// Whether `/health` names the apps server.
  bool present;

  /// How many times [available] asked the server, rather than remembering.
  int asked = 0;
  bool? _remembered;

  final List<String> calls = [];
  final Map<String, Exception> errors = {};

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

  void _fail(String method) {
    if (errors[method] case final error?) throw error;
  }

  @override
  Future<bool> available({bool again = false}) async {
    calls.add('available${again ? ':again' : ''}');
    if (again || _remembered == null) {
      asked++;
      _remembered = present;
    }
    return _remembered!;
  }

  @override
  Future<List<ServerApp>> apps(String workspace) async {
    calls.add('apps:$workspace');
    _fail('apps');
    return [...?spaces[workspace]];
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
    Object? data;
    var upto = 0;
    for (final entry in lines) {
      if (line != null && entry.n > line) break;
      upto = entry.n;
      for (final op in entry.json['patch'] as List? ?? const []) {
        data = _apply(data, op as Map);
      }
    }
    return AppState(upto, data);
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
    return [...?commits[app]];
  }

  @override
  Future<String> diff(AppRef app, String commit) async {
    calls.add('diff:$commit');
    _fail('diff');
    return diffs[commit] ?? '';
  }

  @override
  Future<int> restore(AppRef app, int line) async {
    calls.add('restore:$line');
    _fail('restore');
    final folder = folders[app]!;
    final log = folder['log.jsonl'] ?? '';
    final state = await this.state(app, line: line);
    final n = logLinesOf(log).length + 1;
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
    final made = AppCommit(
      commit: 'ffffffff${commits[app]!.length}',
      by: 'you',
      message:
          'Revert "${commits[app]!.firstWhere((c) => c.commit == commit).message}"',
      files: const ['app.json'],
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

  @override
  Future<Uint8List> card(Uri url) async {
    cardAsks.add(url);
    _fail('card');
    return cards[url] ?? pixel;
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
      message: 'Ticks move to the bottom',
      files: const ['page.html'],
    ),
    AppCommit(
      commit: '1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d',
      t: DateTime.utc(2026, 10, 12, 8, 0),
      by: 'agent',
      message: 'Make Groceries',
      files: const ['app.json', 'page.html'],
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
