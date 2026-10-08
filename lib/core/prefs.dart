// What the app remembers between runs besides the connection.

import 'dart:convert';

/// A document switched off in a workspace: no longer embedded there, but still listed in its
/// Sources so it can be switched back on.
class OffDoc {
  const OffDoc({required this.path, required this.title, this.words});

  final String path;
  final String title;
  final int? words;

  Map<String, Object?> toJson() => {
    'path': path,
    'title': title,
    if (words != null) 'words': words,
  };

  static OffDoc? fromJson(Object? json) {
    if (json is! Map) return null;
    final path = json['path'];
    final title = json['title'];
    if (path is! String || path.isEmpty) return null;
    return OffDoc(
      path: path,
      title: title is String && title.isNotEmpty ? title : path,
      words: json['words'] is int ? json['words'] as int : null,
    );
  }
}

/// The workspace and chat last on screen, which the app opens at start when they still exist.
class LastChat {
  const LastChat(this.slug, [this.thread, this.server]);

  final String slug;

  /// The chat, or null when the workspace was left on a draft.
  final String? thread;

  /// The address of the server it is on, or null when it was saved before servers were told
  /// apart.
  final String? server;

  @override
  bool operator ==(Object other) =>
      other is LastChat &&
      other.slug == slug &&
      other.thread == thread &&
      other.server == server;

  @override
  int get hashCode => Object.hash(slug, thread, server);

  Map<String, Object?> toJson() => {
    'slug': slug,
    if (thread != null) 'thread': thread,
    if (server != null) 'server': server,
  };

  static LastChat? fromJson(Object? json) {
    if (json is! Map) return null;
    final slug = json['slug'];
    final thread = json['thread'];
    final server = json['server'];
    if (slug is! String || slug.isEmpty) return null;
    return LastChat(
      slug,
      thread is String && thread.isNotEmpty ? thread : null,
      server is String && server.isNotEmpty ? server : null,
    );
  }
}

/// Which colours the app uses: the system's light or dark, or one of them always.
enum ThemePref { system, light, dark }

/// How large the text of a chat is drawn.
enum TextSize {
  small(0.9),
  normal(1),
  large(1.2);

  const TextSize(this.scale);

  /// What the chat's text size is multiplied by.
  final double scale;
}

/// A chat behaviour the person switches on or off, with whether it is on before they choose.
enum ChatSwitch {
  /// Sends a dictated message when listening ends, rather than leaving it in the message box.
  sendDictation(false),

  /// Reads each finished answer aloud as soon as it arrives.
  readAnswers(false),

  /// Marks misspelled words in the message box.
  spellcheck(true),

  /// Keeps the newest text of a streaming answer in view while the chat is at its bottom.
  followAnswer(true),

  /// Shows how each answer ran, its model, time, tokens, speed and cost, under it, rather than
  /// only in its More menu.
  answerDetails(false);

  const ChatSwitch(this.byDefault);

  final bool byDefault;
}

class Prefs {
  const Prefs({
    this.switchedOff = const {},
    this.workspaceOrder = const [],
    this.theme = ThemePref.system,
    this.textSize = TextSize.normal,
    this.lastChat,
    this.switches = const {},
    this.pinned = const {},
    this.recent = const {},
    this.seen = const {},
  });

  /// How many chats [recent] keeps for a workspace.
  static const recentMax = 10;

  /// The documents switched off in each workspace, by [offKey]: its server's address and its
  /// slug, since two servers can each have a workspace of the same name. A key that is a slug
  /// alone was saved before servers were told apart; [adoptedBy] gives it a server.
  final Map<String, List<OffDoc>> switchedOff;

  /// The slugs of the workspaces in the order the person arranged them. A workspace not listed
  /// follows the listed ones.
  final List<String> workspaceOrder;

  final ThemePref theme;
  final TextSize textSize;

  /// The workspace and chat last on screen, or null before any was opened.
  final LastChat? lastChat;

  /// The chat switches the person set; one not here is [ChatSwitch.byDefault].
  final Map<ChatSwitch, bool> switches;

  /// The chats pinned in each workspace, by [offKey], in the order they were pinned.
  /// AnythingLLM keeps no pins, so they are this device's.
  final Map<String, List<String>> pinned;

  /// The chats this device used last in each workspace, by [offKey], last used first, at most
  /// [recentMax] a workspace. The server sends no time for a chat.
  final Map<String, List<String>> recent;

  /// When each chat was last on screen on this device, in milliseconds since the epoch, by
  /// [offKey] and then the chat's slug. An answer the relay finished after it shows as ready.
  final Map<String, Map<String, int>> seen;

  /// When chat [thread] of workspace [slug] on [server] was last on screen, or null when it
  /// never was on this device.
  DateTime? seenAt(String server, String slug, String thread) =>
      switch (seen[offKey(server, slug)]?[thread]) {
        final ms? => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        null => null,
      };

  /// How many chats [seen] keeps for a workspace.
  static const seenMax = 50;

  /// These prefs with chat [thread] of workspace [slug] on [server] seen [at], keeping the
  /// [seenMax] seen last.
  Prefs withSeen(String server, String slug, String thread, DateTime at) {
    final key = offKey(server, slug);
    final kept = {...?seen[key]}..remove(thread);
    final newest = kept.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _copy(
      seen: {
        ...seen,
        key: {
          thread: at.millisecondsSinceEpoch,
          for (final e in newest.take(seenMax - 1)) e.key: e.value,
        },
      },
    );
  }

  /// The chats pinned in workspace [slug] on [server].
  List<String> pinnedIn(String server, String slug) =>
      pinned[offKey(server, slug)] ?? const [];

  /// The chats this device used last in workspace [slug] on [server], last used first.
  List<String> recentIn(String server, String slug) =>
      recent[offKey(server, slug)] ?? const [];

  bool isOn(ChatSwitch which) => switches[which] ?? which.byDefault;

  /// The key of workspace [slug] on [server] in [switchedOff]. Neither an address nor a slug
  /// holds a space.
  static String offKey(String server, String slug) => '$server $slug';

  List<OffDoc> offIn(String server, String slug) =>
      switchedOff[offKey(server, slug)] ?? const [];

  /// Whether some of these prefs were saved before servers were told apart.
  bool get hasUnowned =>
      switchedOff.keys.any((k) => !k.contains(' ')) ||
      (lastChat != null && lastChat!.server == null);

  /// [a] and [b] as one list, one document a path, [b]'s where both have it.
  static List<OffDoc> _merged(List<OffDoc> a, List<OffDoc> b) => {
    for (final doc in a) doc.path: doc,
    for (final doc in b) doc.path: doc,
  }.values.toList();

  /// These prefs with what was saved before servers were told apart given to [server]: in the
  /// app's use until then, one server had them all.
  Prefs adoptedBy(String server) {
    final adopted = <String, List<OffDoc>>{};
    for (final MapEntry(:key, :value) in switchedOff.entries) {
      final owned = key.contains(' ') ? key : offKey(server, key);
      adopted[owned] = _merged(adopted[owned] ?? const [], value);
    }
    return _copy(
      switchedOff: adopted,
      lastChat: () => lastChat == null || lastChat!.server != null
          ? lastChat
          : LastChat(lastChat!.slug, lastChat!.thread, server),
    );
  }

  /// [items] with those named in [workspaceOrder] first, in that order, and the rest after them
  /// in their own order. [slugOf] names an item's workspace.
  List<T> inOrder<T>(Iterable<T> items, String Function(T) slugOf) {
    final rank = {for (final (i, slug) in workspaceOrder.indexed) slug: i};
    final unlisted = rank.length;
    final list = items.toList();
    final keyed = [for (final (i, item) in list.indexed) (i, item)];
    keyed.sort((a, b) {
      final byRank = (rank[slugOf(a.$2)] ?? unlisted).compareTo(
        rank[slugOf(b.$2)] ?? unlisted,
      );
      return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
    });
    return [for (final (_, item) in keyed) item];
  }

  Prefs _copy({
    Map<String, List<OffDoc>>? switchedOff,
    List<String>? workspaceOrder,
    ThemePref? theme,
    TextSize? textSize,
    LastChat? Function()? lastChat,
    Map<ChatSwitch, bool>? switches,
    Map<String, List<String>>? pinned,
    Map<String, List<String>>? recent,
    Map<String, Map<String, int>>? seen,
  }) => Prefs(
    switchedOff: switchedOff ?? this.switchedOff,
    workspaceOrder: workspaceOrder ?? this.workspaceOrder,
    theme: theme ?? this.theme,
    textSize: textSize ?? this.textSize,
    lastChat: lastChat == null ? this.lastChat : lastChat(),
    switches: switches ?? this.switches,
    pinned: pinned ?? this.pinned,
    recent: recent ?? this.recent,
    seen: seen ?? this.seen,
  );

  /// [map] with [key] set to [list], or without it when [list] is empty.
  static Map<String, List<T>> _with<T>(
    Map<String, List<T>> map,
    String key,
    List<T> list,
  ) => {
    for (final entry in map.entries)
      if (entry.key != key) entry.key: entry.value,
    if (list.isNotEmpty) key: list,
  };

  /// These prefs with chat [thread] of workspace [slug] on [server] pinned, or not when [on]
  /// is false.
  Prefs withPin(
    String server,
    String slug,
    String thread, {
    required bool on,
  }) => _copy(
    pinned: _with(pinned, offKey(server, slug), [
      ...pinnedIn(server, slug).where((t) => t != thread),
      if (on) thread,
    ]),
  );

  /// These prefs with chat [thread] of workspace [slug] on [server] the last used, keeping the
  /// [recentMax] used last.
  Prefs withUse(String server, String slug, String thread) => _copy(
    recent: _with(recent, offKey(server, slug), [
      thread,
      ...recentIn(server, slug).where((t) => t != thread).take(recentMax - 1),
    ]),
  );

  /// These prefs with chat [thread] of workspace [slug] on [server] neither pinned nor
  /// recent, as when it is deleted.
  Prefs withoutChat(String server, String slug, String thread) =>
      withPin(server, slug, thread, on: false)._copy(
        recent: _with(recent, offKey(server, slug), [
          ...recentIn(server, slug).where((t) => t != thread),
        ]),
        seen: {
          for (final MapEntry(:key, :value) in seen.entries)
            key: key == offKey(server, slug)
                ? ({...value}..remove(thread))
                : value,
        },
      );

  /// Whether chat [thread] of workspace [slug] on [server] is pinned or recent.
  bool keepsChat(String server, String slug, String thread) =>
      pinnedIn(server, slug).contains(thread) ||
      recentIn(server, slug).contains(thread);

  /// Whether workspace [slug] on [server] has a pinned or recent chat.
  bool keepsChatsOf(String server, String slug) =>
      pinned.containsKey(offKey(server, slug)) ||
      recent.containsKey(offKey(server, slug));

  /// These prefs with the switched-off documents of [slug] on [server] set to [docs].
  Prefs withOff(String server, String slug, List<OffDoc> docs) =>
      _copy(switchedOff: _with(switchedOff, offKey(server, slug), docs));

  /// These prefs with the documents at [paths] forgotten in every workspace on [server].
  Prefs withoutDocs(String server, Set<String> paths) => _copy(
    switchedOff: {
      for (final MapEntry(:key, :value) in switchedOff.entries)
        if (!key.startsWith('$server '))
          key: value
        else if (value.where((d) => !paths.contains(d.path)).toList()
            case final kept when kept.isNotEmpty)
          key: kept,
    },
  );

  /// These prefs with the workspaces arranged as [slugs], and every other slug in the order
  /// kept after them, as another server's workspaces are.
  Prefs withOrder(List<String> slugs) => _copy(
    workspaceOrder: [
      ...slugs,
      ...workspaceOrder.where((s) => !slugs.contains(s)),
    ],
  );

  /// Whether the last chat is in workspace [slug] on [server].
  bool lastChatIn(String server, String slug) =>
      lastChat?.slug == slug && lastChat?.server == server;

  /// These prefs with the order, switched-off documents and last chat of workspace [from] on
  /// [server] moved to [to], as when a workspace's slug changes.
  Prefs withRenamedWorkspace(String server, String from, String to) {
    if (from == to) return this;
    final fromKey = offKey(server, from);
    final toKey = offKey(server, to);
    return _copy(
      switchedOff: {
        for (final entry in switchedOff.entries)
          if (entry.key != fromKey && entry.key != toKey)
            entry.key: entry.value,
        if (switchedOff.containsKey(fromKey) || switchedOff.containsKey(toKey))
          toKey: _merged(offIn(server, to), offIn(server, from)),
      },
      workspaceOrder: [
        for (final s in workspaceOrder)
          if (s == from) to else if (s != to) s,
      ],
      lastChat: () => lastChatIn(server, from)
          ? LastChat(to, lastChat!.thread, server)
          : lastChat,
      pinned: _moved(pinned, fromKey, toKey),
      recent: _moved(recent, fromKey, toKey),
      seen: {
        for (final MapEntry(:key, :value) in seen.entries)
          if (key != fromKey) key: value,
        toKey: ?seen[fromKey],
      },
    );
  }

  /// [map] with what is under [from] under [to] instead.
  static Map<String, List<String>> _moved(
    Map<String, List<String>> map,
    String from,
    String to,
  ) => map.containsKey(from)
      ? _with(_with(map, from, const []), to, map[from]!)
      : map;

  /// These prefs with [slug] dropped from the order, and from the last chat when it is on
  /// [server], as when the workspace is deleted.
  Prefs withoutWorkspace(String server, String slug) => _copy(
    workspaceOrder: [...workspaceOrder.where((s) => s != slug)],
    lastChat: () => lastChatIn(server, slug) ? null : lastChat,
    pinned: _with(pinned, offKey(server, slug), const []),
    recent: _with(recent, offKey(server, slug), const []),
    seen: {...seen}..remove(offKey(server, slug)),
  );

  /// These prefs with chat [thread] of workspace [slug] on [server] as the last on screen; a
  /// null [thread] is a draft.
  Prefs withLastChat(String server, String slug, String? thread) =>
      _copy(lastChat: () => LastChat(slug, thread, server));

  Prefs withTheme(ThemePref theme) => _copy(theme: theme);

  Prefs withTextSize(TextSize size) => _copy(textSize: size);

  Prefs withSwitch(ChatSwitch which, bool on) =>
      _copy(switches: {...switches, which: on});

  String encode() => jsonEncode({
    'switchedOff': {
      for (final entry in switchedOff.entries)
        entry.key: [for (final doc in entry.value) doc.toJson()],
    },
    'workspaceOrder': workspaceOrder,
    'theme': theme.name,
    'textSize': textSize.name,
    if (lastChat != null) 'lastChat': lastChat!.toJson(),
    'chat': {
      for (final MapEntry(:key, :value) in switches.entries) key.name: value,
    },
    if (pinned.isNotEmpty) 'pinned': pinned,
    if (recent.isNotEmpty) 'recent': recent,
    if (seen.isNotEmpty) 'seen': seen,
  });

  /// Reads what [encode] wrote. Anything it cannot read falls back to the default, and keys it
  /// no longer uses, such as the old `groundedOnly`, are ignored.
  static Prefs decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return const Prefs();
    }
    if (json is! Map) return const Prefs();
    final off = json['switchedOff'];
    final order = json['workspaceOrder'];
    final chat = json['chat'];
    final switchNamed = ChatSwitch.values.asNameMap();
    return Prefs(
      switchedOff: {
        if (off is Map)
          for (final entry in off.entries)
            if (entry.key is String && entry.value is List)
              entry.key as String: [
                for (final doc in entry.value as List) ?OffDoc.fromJson(doc),
              ],
      },
      workspaceOrder: [
        if (order is List)
          for (final slug in order)
            if (slug is String) slug,
      ],
      theme: ThemePref.values.asNameMap()[json['theme']] ?? ThemePref.system,
      textSize:
          TextSize.values.asNameMap()[json['textSize']] ?? TextSize.normal,
      lastChat: LastChat.fromJson(json['lastChat']),
      switches: {
        if (chat is Map)
          for (final MapEntry(:key, :value) in chat.entries)
            if (switchNamed[key] case final which? when value is bool)
              which: value,
      },
      pinned: _chatsOf(json['pinned']),
      recent: _chatsOf(json['recent']),
      seen: {
        if (json['seen'] case final Map byWorkspace)
          for (final MapEntry(:key, :value) in byWorkspace.entries)
            if (key is String && value is Map)
              key: {
                for (final MapEntry(key: thread, value: ms) in value.entries)
                  if (thread is String && ms is int) thread: ms,
              },
      },
    );
  }

  /// Each workspace's chat slugs in [json], as [pinned] and [recent] are written.
  static Map<String, List<String>> _chatsOf(Object? json) => {
    if (json is Map)
      for (final MapEntry(:key, :value) in json.entries)
        if (key is String && value is List)
          if ([
                for (final t in value)
                  if (t is String) t,
              ]
              case final threads when threads.isNotEmpty)
            key: threads,
  };
}
