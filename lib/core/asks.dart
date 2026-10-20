import 'json.dart';

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
  final DateTime expires;

  /// What the person decided, or null while the skill waits.
  final AskDecision? decision;

  /// Whether the skill has stopped waiting at [now].
  bool expiredAt(DateTime now) => !now.isBefore(expires);

  /// The request as the bridge gives it, or null for anything else.
  static Ask? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = textOrNull(json['id']);
    final host = textOrNull(json['host']);
    final workspace = textOrNull(json['workspace']);
    final expires = timeOrNull(json['expires']);
    if (id == null ||
        !_askId.hasMatch(id) ||
        host == null ||
        workspace == null ||
        expires == null) {
      return null;
    }
    return Ask(
      id: id,
      host: host,
      origin: textOrNull(json['origin']) ?? host,
      skill: textOrNull(json['skill']) ?? 'A skill',
      workspace: workspace,
      why: textOrNull(json['why']) ?? '',
      expires: expires,
      decision: AskDecision.fromServer(json['decision']),
    );
  }
}

/// The request a bridge answer holds under `ask`, or null.
Ask? askOf(Object? json) => Ask.fromJson(json is Map ? json['ask'] : null);

/// An address the person always allows skills to reach: one origin, its scheme, host and port,
/// and when, if the bridge said. Another port on the same host still asks.
class AllowedOrigin {
  const AllowedOrigin(this.origin, {this.added});

  final String origin;
  final DateTime? added;
}

/// The always-allowed addresses a bridge answer lists under `origins`.
List<AllowedOrigin> allowedOriginsOf(Object? json) {
  final origins = json is Map ? json['origins'] : null;
  return [
    if (origins is List)
      for (final entry in origins)
        if (entry case {'origin': final String origin} when origin.isNotEmpty)
          AllowedOrigin(origin, added: timeOrNull(entry['added'])),
  ];
}

final _askId = RegExp(r'^[0-9a-f]{32}$');

/// The mark a skill's status line ends with while it waits for the person: ` [ask:<id>]`, the
/// request's id in its group.
final askMark = RegExp(r'\s*\[ask:([0-9a-f]{32})\]\s*$');
