// Searching names.

import 'server_models.dart';

/// Whether [text] contains [query], ignoring case and the spaces around the query. An empty
/// query matches everything.
bool matchesSearch(String query, String text) {
  final wanted = query.trim().toLowerCase();
  return wanted.isEmpty || text.toLowerCase().contains(wanted);
}

/// What a search for [query] finds across workspaces: each of [workspaces], in the order given,
/// whose name matches or that holds a chat whose name does, with its matching chats, newest made
/// first. [threadsOf] lists a workspace's chats as the server does, oldest made first.
List<(Workspace, List<Thread>)> findChats(
  String query,
  Iterable<Workspace> workspaces,
  List<Thread> Function(String slug) threadsOf,
) => [
  for (final w in workspaces)
    if ([
          for (final thread in threadsOf(w.slug).reversed)
            if (matchesSearch(query, thread.name)) thread,
        ]
        case final threads
        when threads.isNotEmpty || matchesSearch(query, w.name))
      (w, threads),
];
