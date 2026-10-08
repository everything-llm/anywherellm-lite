import 'prefs.dart';
import 'server_models.dart';

/// A workspace's chats as the sidebar lists them: the [pinned] ones, the [recent] ones this
/// device used last, and the [rest]. No chat is in two of them.
typedef ChatGroups = ({
  List<Thread> pinned,
  List<Thread> recent,
  List<Thread> rest,
});

/// Groups [threads], in the server's order (oldest made first), by the slugs [pinned] and
/// when this device [used] each chat: pinned chats newest made first; then the
/// [Prefs.recentMax] last used, last used first; then every other chat newest made first.
ChatGroups groupChats(
  List<Thread> threads,
  List<String> pinned,
  Map<String, int> used,
) {
  final newest = threads.reversed.toList();
  final pins = pinned.toSet();
  final recent = [
    for (final t in newest)
      if (!pins.contains(t.slug) && used.containsKey(t.slug)) t,
  ]..sort((a, b) => used[b.slug]!.compareTo(used[a.slug]!));
  final kept = recent.take(Prefs.recentMax).toList();
  final inRecent = {for (final t in kept) t.slug};
  return (
    pinned: [
      for (final t in newest)
        if (pins.contains(t.slug)) t,
    ],
    recent: kept,
    rest: [
      for (final t in newest)
        if (!pins.contains(t.slug) && !inRecent.contains(t.slug)) t,
    ],
  );
}
