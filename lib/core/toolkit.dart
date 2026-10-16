import 'companion.dart';

/// The toolkit, anythingllm-suite's bridge, as a [Companion]: it passes the routes of
/// AnythingLLM's internal API (`/api`) its owner allows, for the developer key. The app uses it
/// for what AnythingLLM keeps behind its web login: the saved memories and the scheduled jobs.
/// Before the suite it was anythingllm-toolkit, whose `/health` and saved address still count.
const toolkitCompanion = Companion(
  service: 'anythingllm-bridge',
  formerly: ['anythingllm-toolkit'],
  port: 8467,
  name: 'The toolkit',
  code: 'toolkit',
);

/// Every companion the app knows.
const knownCompanions = [toolkitCompanion];

/// [key], under which an older version kept a companion's address, as the app keys it now: a
/// companion's [Companion.code] in place of any of its [Companion.names], and any other key as it
/// is.
String companionKey(String key) =>
    knownCompanions.where((c) => c.names.contains(key)).firstOrNull?.code ??
    key;

/// The features the app finds in what the toolkit allows ([bridgeFeatures]).
abstract final class ToolkitFeature {
  static const memories = 'memories';
  static const jobs = 'jobs';

  /// Whether the scheduled jobs can be made, changed, run and deleted, not only listed.
  static const jobsWrite = 'jobs-write';

  /// Whether the apps and files the agent made are listed. No route serves it yet.
  static const library = 'library';

  /// Whether what the agent did is listed. No route serves it yet.
  static const activity = 'activity';
}

const _methods = {'GET', 'POST', 'PUT', 'DELETE'};

/// One entry of the toolkit's allow list, `[METHOD ]/path/prefix`: a [method], or null for all
/// four, on any path whose first segments are [prefix].
class BridgeRule {
  const BridgeRule(this.method, this.prefix);

  /// The rule [entry] writes, or null for one that is not a rule, as the toolkit reads them.
  static BridgeRule? parse(String entry) {
    final text = entry.trim();
    final space = text.lastIndexOf(' ');
    final method = space < 0
        ? ''
        : text.substring(0, space).trim().toUpperCase();
    final path = text.substring(space + 1);
    if (method.isNotEmpty && !_methods.contains(method)) return null;
    if (!path.startsWith('/') || path == '/') return null;
    final prefix = _segments(path);
    if (prefix == null) return null;
    return BridgeRule(method.isEmpty ? null : method, prefix);
  }

  final String? method;
  final List<String> prefix;

  /// Whether the rule passes [method] on [path], which starts with `/`.
  bool permits(String method, String path) {
    final segments = _segments(path);
    if (segments == null || segments.length < prefix.length) return false;
    if (this.method != null && this.method != method) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (segments[i] != prefix[i]) return false;
    }
    return true;
  }

  /// [path]'s segments, or null for a path with an empty, `.` or `..` segment.
  static List<String>? _segments(String path) {
    final trimmed = path.replaceAll(RegExp(r'^/+|/+$'), '');
    final segments = trimmed.split('/');
    final bad = segments.any(
      (s) => s.isEmpty || s == '.' || s == '..' || s.contains(r'\'),
    );
    return bad ? null : segments;
  }
}

/// The rules a toolkit's `/health` answer allows, under `allow`; none for any other answer.
List<BridgeRule> bridgeRules(Object? health) {
  final allow = health is Map ? health['allow'] : null;
  return [
    if (allow is List)
      for (final entry in allow)
        if (entry is String) ?BridgeRule.parse(entry),
  ];
}

/// The calls that read the scheduled jobs, which changing them needs too.
const _jobReads = [
  ('GET', '/scheduled-jobs'),
  ('GET', '/scheduled-jobs/1/runs'),
];

/// Each feature's calls, as a method and a path with a stand-in for each id and slug.
const _featureCalls = {
  ToolkitFeature.memories: [
    ('GET', '/workspaces/x/memories'),
    ('POST', '/workspaces/x/memories'),
    ('PUT', '/memories/1'),
    ('DELETE', '/memories/1'),
    ('POST', '/memories/1/promote'),
    ('POST', '/memories/1/demote/x'),
    ('GET', '/admin/system-preferences-for'),
    ('POST', '/admin/system-preferences'),
  ],
  ToolkitFeature.jobs: _jobReads,
  ToolkitFeature.jobsWrite: [
    ..._jobReads,
    ('POST', '/scheduled-jobs/new'),
    ('PUT', '/scheduled-jobs/1'),
    ('DELETE', '/scheduled-jobs/1'),
    ('POST', '/scheduled-jobs/1/trigger'),
  ],
};

/// The features [rules] let through: each one whose every call some rule permits.
Set<String> bridgeFeatures(List<BridgeRule> rules) => {
  for (final MapEntry(key: feature, value: calls) in _featureCalls.entries)
    if (calls.every(
      (call) => rules.any((rule) => rule.permits(call.$1, call.$2)),
    ))
      feature,
};
