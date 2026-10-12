import 'host_routes.dart';

/// How many saved memories AnythingLLM keeps for every workspace.
const globalMemoryLimit = 5;

/// How many saved memories AnythingLLM keeps for each workspace.
const workspaceMemoryLimit = 20;

/// The longest fact either memory takes, in characters.
const memoryTextMax = 500;

/// One of AnythingLLM's saved memories: a short fact every chat of its workspace, or of every
/// workspace when [global], is shown word for word.
class SavedMemory {
  const SavedMemory({
    required this.id,
    required this.text,
    required this.global,
  });

  final int id;
  final String text;
  final bool global;

  /// The memory as the server gives it (`id`, `content`, `scope`), or null for anything else.
  static SavedMemory? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final text = json['content'];
    if (id is! num || text is! String) return null;
    return SavedMemory(
      id: id.toInt(),
      text: text,
      global: json['scope'] == 'global',
    );
  }
}

/// The saved memories a workspace's chats are shown: those for every workspace and its own.
class SavedMemories {
  const SavedMemories({this.global = const [], this.workspace = const []});

  final List<SavedMemory> global;
  final List<SavedMemory> workspace;

  /// The memories as `GET /api/workspaces/{slug}/memories` answers them, under `memories`.
  static SavedMemories fromJson(Object? json) {
    final memories = json is Map ? json['memories'] : null;
    List<SavedMemory> listed(Object? list) => [
      if (list is List)
        for (final item in list) ?SavedMemory.fromJson(item),
    ];
    if (memories is! Map) return const SavedMemories();
    return SavedMemories(
      global: listed(memories['global']),
      workspace: listed(memories['workspace']),
    );
  }
}

/// Whether AnythingLLM keeps saved memories at all, and whether it also saves them itself from
/// what it notices in chats.
class MemorySwitches {
  const MemorySwitches({required this.enabled, required this.learn});

  final bool enabled;
  final bool learn;

  /// The switches as the server's preferences give them, under `settings`: `memory_enabled` is
  /// off unless `true`, and `memory_auto_extraction` on unless `false`, as AnythingLLM reads them.
  static MemorySwitches fromJson(Object? json) {
    final settings = json is Map ? json['settings'] : null;
    final values = settings is Map ? settings : const {};
    return MemorySwitches(
      enabled: '${values['memory_enabled']}' == 'true',
      learn: '${values['memory_auto_extraction']}' != 'false',
    );
  }
}

/// A fact in the everythingllm host's long-term memory, which no chat is shown but the agent
/// recalls by meaning. Its [id] is `m<number>`.
class LongFact {
  const LongFact({
    required this.id,
    required this.text,
    required this.global,
    this.created,
  });

  final String id;
  final String text;

  /// Whether every workspace's agent may recall it, rather than this workspace's alone.
  final bool global;
  final DateTime? created;

  static LongFact? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final text = json['text'];
    if (id is! String || text is! String) return null;
    return LongFact(
      id: id,
      text: text,
      global: json['scope'] == 'global',
      created: _time(json['created']),
    );
  }
}

/// A sandbox file whose text the long-term memory keeps, in [parts], by its sandbox [path].
class LongFile {
  const LongFile({required this.path, required this.parts, this.ingested});

  final String path;
  final int parts;
  final DateTime? ingested;

  static LongFile? fromJson(Object? json) {
    if (json is! Map) return null;
    final path = json['path'];
    final parts = json['parts'];
    if (path is! String || parts is! num) return null;
    return LongFile(
      path: path,
      parts: parts.toInt(),
      ingested: _time(json['ingested']),
    );
  }
}

/// What a workspace's agent can recall from the long-term memory: the newest [facts] of the
/// [count] it holds, the [files] read in, those still [waiting] to be read with the parts left,
/// and those that [failed] with why.
class LongMemory {
  const LongMemory({
    this.count = 0,
    this.facts = const [],
    this.files = const [],
    this.waiting = const [],
    this.failed = const [],
  });

  final int count;
  final List<LongFact> facts;
  final List<LongFile> files;
  final List<LongFile> waiting;
  final List<({String path, String error})> failed;

  /// The memory as the host's `GET /_live/memory/<workspace>` gives it, or null for an answer
  /// that is not one.
  static LongMemory? fromJson(Object? json) {
    if (json is! Map || json['facts'] is! List) return null;
    List<T> listed<T>(Object? list, T? Function(Object?) read) => [
      if (list is List)
        for (final item in list) ?read(item),
    ];
    final count = json['count'];
    return LongMemory(
      count: count is num ? count.toInt() : 0,
      facts: listed(json['facts'], LongFact.fromJson),
      files: listed(json['files'], LongFile.fromJson),
      waiting: listed(json['waiting'], LongFile.fromJson),
      failed: listed(
        json['failed'],
        (item) => switch (item) {
          {'path': final String path, 'error': final String error} => (
            path: path,
            error: error,
          ),
          _ => null,
        },
      ),
    );
  }
}

/// A fact or a part of a file the long-term memory finds for a query, and how close it is in
/// meaning, from 0 to 1. A [fact] is null for a file's part, which has its [path] and [part].
class RecallHit {
  const RecallHit({
    required this.score,
    required this.text,
    this.fact,
    this.path,
    this.part,
  });

  final double score;
  final String text;
  final LongFact? fact;
  final String? path;
  final int? part;

  static RecallHit? fromJson(Object? json) {
    if (json is! Map) return null;
    final score = json['score'];
    final text = json['text'];
    if (score is! num || text is! String) return null;
    final path = json['path'];
    final part = json['part'];
    return RecallHit(
      score: score.toDouble(),
      text: text,
      fact: json['id'] is String ? LongFact.fromJson(json) : null,
      path: path is String ? path : null,
      part: part is num ? part.toInt() : null,
    );
  }
}

/// The host's long-term memory route for workspace [slug], with [tail] and [query].
Uri memoryRoute(
  Uri server,
  String slug, [
  String tail = '',
  Map<String, String>? query,
]) => liveRoute(server, 'memory/${Uri.encodeComponent(slug)}$tail', query);

/// When a fact was kept, in words: Today, Yesterday, `3 Oct`, or `3 Oct 2025` in another year.
String keptText(DateTime when, DateTime now) {
  final day = DateTime(when.year, when.month, when.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final date = '${when.day} ${months[when.month - 1]}';
  return when.year == now.year ? date : '$date ${when.year}';
}

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;
