/// What the person answers a skill that asks to reach a host on their own network: allow it for
/// the rest of the answer ([once]), allow it from now on ([always]), or refuse it ([deny]).
enum AskDecision {
  once,
  always,
  deny;

  /// The decision the bridge calls [value], or null for none it knows.
  static AskDecision? fromServer(Object? value) =>
      values.where((d) => d.name == value).firstOrNull;
}

/// An anywherellm-suite skill's request, held by the toolkit's bridge, to reach [host], which
/// its fence keeps the agent from, while a chat answer runs. The skill waits for the person's
/// [decision] until [expires], then refuses. [why] is written by the skill's code, never by
/// the model; [origin] is the scheme, host and port, never a path.
class Ask {
  const Ask({
    required this.id,
    required this.host,
    required this.origin,
    required this.skill,
    required this.workspace,
    required this.why,
    required this.asked,
    required this.expires,
    this.decision,
  });

  final String id;
  final String host;
  final String origin;
  final String skill;

  /// The slug of the workspace whose answer asks.
  final String workspace;
  final String why;
  final DateTime asked;
  final DateTime expires;

  /// What the person decided, or null while the skill waits.
  final AskDecision? decision;

  /// Whether the skill has stopped waiting at [now].
  bool expiredAt(DateTime now) => !now.isBefore(expires);

  /// The request as the bridge gives it, or null for anything else.
  static Ask? fromJson(Object? json) {
    if (json is! Map) return null;
    String? text(String key) => switch (json[key]) {
      final String value when value.trim().isNotEmpty => value.trim(),
      _ => null,
    };
    final id = text('id');
    final host = text('host');
    final workspace = text('workspace');
    final asked = DateTime.tryParse(text('asked') ?? '');
    final expires = DateTime.tryParse(text('expires') ?? '');
    if (id == null ||
        !_askId.hasMatch(id) ||
        host == null ||
        workspace == null ||
        asked == null ||
        expires == null) {
      return null;
    }
    return Ask(
      id: id,
      host: host,
      origin: text('origin') ?? host,
      skill: text('skill') ?? 'A skill',
      workspace: workspace,
      why: text('why') ?? '',
      asked: asked,
      expires: expires,
      decision: AskDecision.fromServer(json['decision']),
    );
  }
}

/// The request a bridge answer holds under `ask`, or null.
Ask? askOf(Object? json) => Ask.fromJson(json is Map ? json['ask'] : null);

/// A host the person always allows skills to reach, and when, if the bridge said.
class AllowedHost {
  const AllowedHost(this.host, {this.added});

  final String host;
  final DateTime? added;
}

/// The always-allowed hosts a bridge answer lists under `hosts`.
List<AllowedHost> allowedHostsOf(Object? json) {
  final hosts = json is Map ? json['hosts'] : null;
  return [
    if (hosts is List)
      for (final entry in hosts)
        if (entry case {'host': final String host} when host.trim().isNotEmpty)
          AllowedHost(
            host.trim(),
            added: DateTime.tryParse('${entry['added'] ?? ''}'),
          ),
  ];
}

final _askId = RegExp(r'^[0-9a-f]{32}$');

/// The mark a skill's status line ends with while it waits for the person: ` [ask:<id>]`.
final askMark = RegExp(r'\s*\[ask:([0-9a-f]{32})\]\s*$');

/// The request an agent's status [thought] says it waits for, or null.
String? askIdIn(String thought) => askMark.firstMatch(thought.trim())?[1];
