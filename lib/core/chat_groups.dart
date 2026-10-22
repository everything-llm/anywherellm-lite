import 'server_models.dart';

/// A workspace's chats as the drawer lists them: the [pinned] ones, the [recent] ones this
/// device used last, and the [rest]. No chat is in two of them.
typedef ChatGroups = ({
  List<Thread> pinned,
  List<Thread> recent,
  List<Thread> rest,
});

/// Groups [threads], in the server's order (oldest made first), by the slugs [pinned] and the
/// slugs this device used last, [recent], last used first: pinned chats newest made first;
/// then the recent ones in their order; then every other chat newest made first. A slug of a
/// chat that is gone counts for nothing.
ChatGroups groupChats(
  List<Thread> threads,
  List<String> pinned,
  List<String> recent,
) {
  final bySlug = {for (final t in threads) t.slug: t};
  final pins = pinned.toSet();
  final used = [
    for (final slug in recent)
      if (!pins.contains(slug)) ?bySlug[slug],
  ];
  final listed = {...pins, for (final t in used) t.slug};
  return (
    pinned: [
      for (final t in threads.reversed)
        if (pins.contains(t.slug)) t,
    ],
    recent: used,
    rest: [
      for (final t in threads.reversed)
        if (!listed.contains(t.slug)) t,
    ],
  );
}

/// [groups] in the order a list of chats shows them, each with whether it is pinned.
List<(Thread, bool)> inListOrder(ChatGroups groups) => [
  for (final thread in groups.pinned) (thread, true),
  for (final thread in [...groups.recent, ...groups.rest]) (thread, false),
];
