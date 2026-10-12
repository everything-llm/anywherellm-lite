import 'dart:convert';

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int? _int(Object? value) => value is int ? value : null;

/// Who wrote a log line or made a commit, in words: `you` is You, `host` is the server.
String byText(String? by) => switch (by) {
  'you' => 'You',
  'agent' => 'Agent',
  'device' => 'Device',
  'host' => 'Server',
  null || '' => 'Unknown',
  final other => other,
};

/// The fields of a log line that only say what it is, never read to compute the state.
const _lineKeys = {'n', 't', 'by', 'ev', 'patch', 'chat', 'wake', 'woke'};

/// One line of an app's `log.jsonl`: its number, time, writer and event, the fields that
/// describe it, and the line as it was written.
class LogLine {
  const LogLine({
    required this.n,
    required this.json,
    this.t,
    this.by,
    this.ev,
    this.chat,
    this.fields = const {},
  });

  /// The line [text] says, or null when it is not a JSON object with a line number.
  static LogLine? parse(String text) {
    try {
      return fromJson(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }

  /// The line [json] holds, as `GET .../log` answers it, or null when it is not an object with
  /// a line number.
  static LogLine? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final n = json['n'];
    if (n is! int) return null;
    return LogLine(
      n: n,
      json: json,
      t: _time(json['t']),
      by: _text(json['by']),
      ev: _text(json['ev']),
      chat: _text(json['chat']),
      fields: {
        for (final MapEntry(:key, :value) in json.entries)
          if (!_lineKeys.contains(key)) key: value,
      },
    );
  }

  final int n;
  final DateTime? t;
  final String? by;
  final String? ev;

  /// The AnythingLLM thread an agent's change came from.
  final String? chat;

  /// What the line says beyond its number, time, writer, event and patch.
  final Map<String, Object?> fields;

  /// The line as written.
  final Map<String, dynamic> json;

  /// What happened, by its event's name: `made`, `tick`, or `change` for a line with none.
  String get title => ev ?? 'change';

  /// Its fields in one line: `text: Eggs · to: 3`.
  String get detail => [
    for (final MapEntry(:key, :value) in fields.entries)
      '$key: ${value is String ? value : jsonEncode(value)}',
  ].join(' · ');
}

/// The lines of [jsonl], newest first. A line that is not one is left out.
List<LogLine> logLinesOf(String jsonl) => [
  for (final text in const LineSplitter().convert(jsonl))
    if (text.trim().isNotEmpty) ?LogLine.parse(text),
]..sort((a, b) => b.n.compareTo(a.n));

/// One page of an app's log, as `GET .../log` answers it: its [lines] newest first, the
/// [first] line the log holds, its [last] line, and whether lines older than the page remain.
class LogPage {
  const LogPage({
    required this.lines,
    this.first,
    this.last,
    this.more = false,
  });

  /// `GET .../log`'s answer.
  static LogPage fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return LogPage(
      lines: [
        if (map['lines'] case final List lines)
          for (final line in lines) ?LogLine.fromJson(line),
      ]..sort((a, b) => b.n.compareTo(a.n)),
      first: _int(map['first']),
      last: _int(map['last']),
      more: map['more'] == true,
    );
  }

  final List<LogLine> lines;

  /// The first line `log.jsonl` holds, from which the app can be put back.
  final int? first;
  final int? last;
  final bool more;
}

/// An app's data after one line of its log.
class AppState {
  const AppState(this.line, this.data, {this.restorableFrom});

  /// `GET .../state`'s answer.
  static AppState fromJson(Object? json) => AppState(
    json is Map && json['line'] is int ? json['line'] as int : 0,
    json is Map ? json['data'] : null,
    restorableFrom: json is Map ? _int(json['restorable_from']) : null,
  );

  final int line;
  final Object? data;

  /// The first line the log holds, when the server says.
  final int? restorableFrom;
}

/// A commit of an app's folder: a change to `app.json` or `page.html`.
class AppCommit {
  const AppCommit({
    required this.commit,
    this.t,
    this.by,
    this.chat,
    this.message = '',
    this.subject,
    this.body,
    this.files = const [],
    this.revertable,
  });

  final String commit;
  final DateTime? t;
  final String? by;
  final String? chat;

  /// Its message, without its `By:` and `Chat:` trailers.
  final String message;

  /// Its message's first line, as the server splits it; null from a server that does not.
  final String? subject;

  /// Its message after the first line, as the server splits it; null from a server that does
  /// not.
  final String? body;

  final List<String> files;

  /// Whether the server would revert it: false for the first commit and one that changes
  /// `log.jsonl`. Null from a server that does not say.
  final bool? revertable;

  /// Its hash, short: the first seven hex digits.
  String get short => commit.length > 7 ? commit.substring(0, 7) : commit;

  /// Its title: [subject], or the first line of [message].
  String get title =>
      subject ?? const LineSplitter().convert(message).firstOrNull ?? '';

  /// What its message says under the title: [body], or the rest of [message].
  String get details {
    if (body case final said?) return said.trim();
    final lines = const LineSplitter().convert(message);
    return lines.length < 2 ? '' : lines.skip(1).join('\n').trim();
  }

  /// Whether to offer Revert: as [revertable] says, or, from a server that does not say,
  /// unless it is the [first] commit, which the server always refuses.
  bool canRevert({required bool first}) => revertable ?? !first;
}

/// `GET .../history`'s commits, newest first.
List<AppCommit> commitsOf(Object? json) {
  final list = json is Map ? json['commits'] : null;
  return [
    if (list is List)
      for (final entry in list)
        if (entry is Map && entry['commit'] is String)
          AppCommit(
            commit: entry['commit'] as String,
            t: _time(entry['t']),
            by: _text(entry['by']),
            chat: _text(entry['chat']),
            message: entry['message'] is String
                ? (entry['message'] as String).trim()
                : '',
            subject: entry['subject'] is String
                ? (entry['subject'] as String).trim()
                : null,
            body: entry['body'] is String ? entry['body'] as String : null,
            files: [
              if (entry['files'] case final List files)
                for (final file in files)
                  if (file is String) file,
            ],
            revertable: entry['revertable'] is bool
                ? entry['revertable'] as bool
                : null,
          ),
  ];
}

/// What a line of a diff is: the commit's header or a file's, a line added, one removed, or
/// one kept as context.
enum DiffKind { header, added, removed, context }

/// [diff], the text of `git show`, a line at a time with what each is.
List<(DiffKind, String)> diffLines(String diff) {
  const headers = [
    'diff --git',
    '+++',
    '---',
    'index ',
    'new file',
    'deleted file',
    '@@',
  ];
  var inFile = false;
  final lines = <(DiffKind, String)>[];
  for (final line in const LineSplitter().convert(diff)) {
    if (line.startsWith('diff --git')) inFile = true;
    final kind = !inFile || headers.any(line.startsWith)
        ? DiffKind.header
        : line.startsWith('+')
        ? DiffKind.added
        : line.startsWith('-')
        ? DiffKind.removed
        : DiffKind.context;
    lines.add((kind, line));
  }
  return lines;
}

/// [diff], the text of `git show`, from its first file on: the commit's own header says what
/// the sheet already shows. A diff with no file is kept whole.
String diffBody(String diff) {
  final start = diff.indexOf('diff --git');
  return start < 0 ? diff : diff.substring(start);
}

/// [patch], one file's hunks without git's headers, a line at a time with what each is: a
/// hunk's `@@` line and `\ No newline at end of file` are headers.
List<(DiffKind, String)> patchLines(String patch) => [
  for (final line in const LineSplitter().convert(patch))
    (
      line.startsWith('@@') || line.startsWith(r'\')
          ? DiffKind.header
          : line.startsWith('+')
          ? DiffKind.added
          : line.startsWith('-')
          ? DiffKind.removed
          : DiffKind.context,
      line,
    ),
];

/// What a commit did to one file.
enum FileChange { added, modified, deleted }

/// One file of a commit: its path, what the commit did to it, and its hunks.
class FileDiff {
  const FileDiff(this.path, this.status, this.patch);

  final String path;
  final FileChange status;

  /// Its unified diff hunks, from its first `@@` line, without git's headers.
  final String patch;
}

/// A commit's diff: `git show` whole, and file by file where the server splits it.
class AppDiff {
  const AppDiff(this.diff, {this.files});

  /// `GET .../diff`'s answer.
  static AppDiff fromJson(Object? json) {
    final map = json is Map ? json : const {};
    final files = map['files'];
    return AppDiff(
      map['diff'] is String ? map['diff'] as String : '',
      files: files is List
          ? [
              for (final file in files)
                if (file is Map && file['path'] is String)
                  FileDiff(file['path'] as String, switch (file['status']) {
                    'added' => FileChange.added,
                    'deleted' => FileChange.deleted,
                    _ => FileChange.modified,
                  }, file['patch'] is String ? file['patch'] as String : ''),
            ]
          : null,
    );
  }

  /// The text of `git show`.
  final String diff;

  /// Each file the commit changed, or null from a server that does not split the diff.
  final List<FileDiff>? files;
}
