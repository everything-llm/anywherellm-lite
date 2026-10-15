import 'json.dart';
import 'server_models.dart' show jsonObjects;

/// What an [ActivityEvent] is about: a scheduled task's run, a saved action's run, a change to
/// an app, or a file the agent made.
enum ActivityKind { task, action, app, file, other }

/// How an event ended. [unknown] is a word the app does not know, which it shows without a
/// verdict rather than as a success.
enum ActivityOutcome { ok, failed, running, unknown }

/// Where an event leads: a chat's thread, or a page on the server (an app's or a browser tab's).
sealed class ActivityLink {
  const ActivityLink();
}

class ChatLink extends ActivityLink {
  const ChatLink(this.slug, this.thread);

  final String slug;
  final String thread;
}

class PageLink extends ActivityLink {
  const PageLink(this.path);

  /// A path from the root of the server's address.
  final String path;
}

/// One thing the agent did, as the toolkit's Activity lists it, newest first.
class ActivityEvent {
  const ActivityEvent({
    required this.at,
    required this.title,
    required this.kind,
    required this.outcome,
    this.id,
    this.workspace,
    this.detail = '',
    this.link,
  });

  /// An event as the toolkit lists it, or null without a time and a title.
  static ActivityEvent? fromJson(Map<String, dynamic> json) {
    final at = timeOrNull(json['at']);
    final title = json['title'];
    if (at == null || title is! String || title.isEmpty) return null;
    return ActivityEvent(
      id: idOrNull(json['id']),
      at: at,
      title: title,
      kind: switch (json['kind']) {
        'task' => ActivityKind.task,
        'action' => ActivityKind.action,
        'app' => ActivityKind.app,
        'file' => ActivityKind.file,
        _ => ActivityKind.other,
      },
      outcome: switch (json['outcome']) {
        'ok' || 'done' || 'completed' => ActivityOutcome.ok,
        'failed' || 'error' => ActivityOutcome.failed,
        'running' || 'started' => ActivityOutcome.running,
        _ => ActivityOutcome.unknown,
      },
      workspace: textOrNull(json['workspace']),
      detail: textOrNull(json['detail']) ?? '',
      link: switch (json['link']) {
        final String path when path.startsWith('/') => PageLink(path),
        {'slug': final String slug, 'thread': final String thread} => ChatLink(
          slug,
          thread,
        ),
        _ => null,
      },
    );
  }

  final String? id;
  final DateTime at;
  final String title;
  final ActivityKind kind;
  final ActivityOutcome outcome;
  final String? workspace;

  /// What the event left, in a line or two: a result, or why it failed.
  final String detail;
  final ActivityLink? link;

  /// A key that tells the event from the others, for the sheet that shows it.
  String get key => id ?? '${at.toIso8601String()}|$title';
}

/// A batch of events, and whether the toolkit has older ones.
class ActivityEvents {
  const ActivityEvents(this.events, {this.more = false});

  final List<ActivityEvent> events;
  final bool more;
}

/// The events in a toolkit's answer, `events`, each kept when it is whole, and `more` when it
/// says there are older ones.
ActivityEvents activityOf(Object? json) => ActivityEvents([
  for (final event in jsonObjects(json is Map ? json['events'] : json))
    ?ActivityEvent.fromJson(event),
], more: json is Map && json['more'] == true);
