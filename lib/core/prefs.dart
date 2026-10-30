// What the app remembers between runs besides the connection.

import 'dart:convert';

import 'json.dart';
import 'server_models.dart';
import 'shortcuts.dart';
import 'users.dart';

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
    final slug = textOrNull(json['slug']);
    if (slug == null) return null;
    return LastChat(
      slug,
      textOrNull(json['thread']),
      textOrNull(json['server']),
    );
  }
}

/// A message waiting in a chat to be sent when the answer before it ends, as it is kept between
/// runs: its words, the shortcut it was written with, and the names of the files that went with
/// it, whose bytes are not kept.
class SavedOnDeck {
  const SavedOnDeck(this.text, {this.shortcutUse, this.files = const []});

  final String text;
  final ShortcutUse? shortcutUse;
  final List<String> files;

  Map<String, Object?> toJson() => {
    'text': text,
    if (shortcutUse != null) 'shortcutUse': shortcutUse!.toJson(),
    if (files.isNotEmpty) 'files': files,
  };

  static SavedOnDeck? fromJson(Object? json) {
    if (json is! Map) return null;
    final text = textOrNull(json['text']);
    if (text == null) return null;
    final files = json['files'];
    return SavedOnDeck(
      text,
      shortcutUse: ShortcutUse.fromJson(json['shortcutUse']),
      files: [
        if (files is List)
          for (final name in files)
            if (name is String) name,
      ],
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
  answerDetails(false),

  /// Shows a shortcut chip instead of the expanded question it sent.
  hideShortcutPrompts(false);

  const ChatSwitch(this.byDefault);

  final bool byDefault;
}

class Prefs {
  const Prefs({
    this.workspaceOrder = const [],
    this.theme = ThemePref.system,
    this.textSize = TextSize.normal,
    this.lastChat,
    this.switches = const {},
    this.pinned = const {},
    this.recent = const {},
    this.shortcuts = const [],
    this.shortcutUses = const {},
    this.onDeck = const {},
    this.users = const {},
    this.lastFolders = const {},
  });

  /// How many chats [recent] keeps for a workspace.
  static const recentMax = 10;

  /// How many shortcut uses [shortcutUses] remembers across chats.
  static const shortcutUsesMax = 500;

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

  /// User-made prompt shortcuts. Built-in prompts are kept in [builtInPromptShortcuts].
  final List<PromptShortcut> shortcuts;

  /// Shortcut labels and details for exchanges on this device, keyed by server, workspace,
  /// thread and AnythingLLM's exchange id.
  final Map<String, ShortcutUse> shortcutUses;

  /// The messages waiting in each chat, by [chatKey], first to go first, kept so they survive
  /// the app closing.
  final Map<String, List<SavedOnDeck>> onDeck;

  /// Whom this device's chats are saved as on each multi-user server, by the server's address.
  final Map<String, ServerUser> users;

  /// Whom chats are saved as on [server], or null while no one is chosen there.
  ServerUser? userOn(String server) => users[server];

  /// These prefs with chats on [server] saved as [user].
  Prefs withUser(String server, ServerUser user) =>
      _copy(users: {...users, server: user});

  /// The library folder a document was last moved into on each server, by its address, which a
  /// new document goes into.
  final Map<String, String> lastFolders;

  /// The key of chat [thread] of workspace [slug] on [server] in [onDeck].
  static String chatKey(String server, String slug, String thread) =>
      '${offKey(server, slug)} $thread';

  /// The messages waiting in chat [thread] of workspace [slug] on [server].
  List<SavedOnDeck> onDeckIn(String server, String slug, String thread) =>
      onDeck[chatKey(server, slug, thread)] ?? const [];

  /// The chats pinned in workspace [slug] on [server].
  List<String> pinnedIn(String server, String slug) =>
      pinned[offKey(server, slug)] ?? const [];

  /// The chats this device used last in workspace [slug] on [server], last used first.
  List<String> recentIn(String server, String slug) =>
      recent[offKey(server, slug)] ?? const [];

  bool isOn(ChatSwitch which) => switches[which] ?? which.byDefault;

  /// The key of workspace [slug] on [server] in [pinned], [recent] and the like: its server's
  /// address and its slug, since two servers can each have a workspace of the same name.
  /// Neither an address nor a slug holds a space.
  static String offKey(String server, String slug) => '$server $slug';

  /// Whether some of these prefs were saved before servers were told apart.
  bool get hasUnowned => lastChat != null && lastChat!.server == null;

  static String shortcutUseKey(
    String server,
    String slug,
    String thread,
    int chatId,
  ) => '${offKey(server, slug)} $thread $chatId';

  /// These prefs with what was saved before servers were told apart given to [server]: in the
  /// app's use until then, one server had them all.
  Prefs adoptedBy(String server) => _copy(
    lastChat: () => lastChat == null || lastChat!.server != null
        ? lastChat
        : LastChat(lastChat!.slug, lastChat!.thread, server),
  );

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
    List<String>? workspaceOrder,
    ThemePref? theme,
    TextSize? textSize,
    LastChat? Function()? lastChat,
    Map<ChatSwitch, bool>? switches,
    Map<String, List<String>>? pinned,
    Map<String, List<String>>? recent,
    List<PromptShortcut>? shortcuts,
    Map<String, ShortcutUse>? shortcutUses,
    Map<String, List<SavedOnDeck>>? onDeck,
    Map<String, ServerUser>? users,
    Map<String, String>? lastFolders,
  }) => Prefs(
    workspaceOrder: workspaceOrder ?? this.workspaceOrder,
    theme: theme ?? this.theme,
    textSize: textSize ?? this.textSize,
    lastChat: lastChat == null ? this.lastChat : lastChat(),
    switches: switches ?? this.switches,
    pinned: pinned ?? this.pinned,
    recent: recent ?? this.recent,
    shortcuts: shortcuts ?? this.shortcuts,
    shortcutUses: shortcutUses ?? this.shortcutUses,
    onDeck: onDeck ?? this.onDeck,
    users: users ?? this.users,
    lastFolders: lastFolders ?? this.lastFolders,
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

  /// These prefs with [messages] waiting in chat [thread] of workspace [slug] on [server].
  Prefs withOnDeck(
    String server,
    String slug,
    String thread,
    List<SavedOnDeck> messages,
  ) => _copy(onDeck: _with(onDeck, chatKey(server, slug, thread), messages));

  /// These prefs with chat [thread] of workspace [slug] on [server] neither pinned nor
  /// recent, and nothing waiting in it, as when it is deleted.
  Prefs withoutChat(String server, String slug, String thread) =>
      withPin(server, slug, thread, on: false)._copy(
        recent: _with(recent, offKey(server, slug), [
          ...recentIn(server, slug).where((t) => t != thread),
        ]),
        onDeck: _with(onDeck, chatKey(server, slug, thread), const []),
      );

  /// These prefs with nothing waiting in any chat on [server], as when it is forgotten.
  Prefs withoutOnDeckOn(String server) => _copy(
    onDeck: {
      for (final MapEntry(:key, :value) in onDeck.entries)
        if (!key.startsWith('$server ')) key: value,
    },
  );

  /// Whether chat [thread] of workspace [slug] on [server] is pinned or recent, or has messages
  /// waiting.
  bool keepsChat(String server, String slug, String thread) =>
      pinnedIn(server, slug).contains(thread) ||
      recentIn(server, slug).contains(thread) ||
      onDeck.containsKey(chatKey(server, slug, thread));

  /// These prefs with [folder] the library folder of [server] a new document goes into.
  Prefs withLastFolder(String server, String folder) =>
      _copy(lastFolders: {...lastFolders, server: folder});

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

  /// These prefs with what is kept of workspace [from] on [server], its order, last chat, pins,
  /// recent chats, shortcuts and their uses, and the messages waiting in its chats, moved to
  /// [to], as when a workspace's slug changes. Its Main chat's key names the slug
  /// ([mainChatOf]), so it moves too.
  Prefs withRenamedWorkspace(String server, String from, String to) {
    if (from == to) return this;
    final fromKey = offKey(server, from);
    final toKey = offKey(server, to);
    final (fromMain, toMain) = (mainChatOf(from), mainChatOf(to));
    // A chat, or a chat and an exchange id after a space, of the workspace.
    String chat(String key) => key == fromMain || key.startsWith('$fromMain ')
        ? '$toMain${key.substring(fromMain.length)}'
        : key;
    return _copy(
      workspaceOrder: [
        for (final s in workspaceOrder)
          if (s == from) to else if (s != to) s,
      ],
      lastChat: () => lastChatIn(server, from)
          ? LastChat(to, switch (lastChat!.thread) {
              final thread? => chat(thread),
              null => null,
            }, server)
          : lastChat,
      pinned: _moved(pinned, fromKey, toKey),
      recent: _moved(recent, fromKey, toKey),
      shortcuts: [
        for (final shortcut in shortcuts)
          shortcut.workspaceKey == fromKey
              ? shortcut.inWorkspace(toKey)
              : shortcut,
      ],
      shortcutUses: _movedUnder(shortcutUses, fromKey, toKey, chat),
      onDeck: _movedUnder(onDeck, fromKey, toKey, chat),
    );
  }

  /// [map] with each key under workspace key [from], as `<from> <rest>`, under [to] instead, as
  /// `<to> <moved(rest)>`.
  static Map<String, T> _movedUnder<T>(
    Map<String, T> map,
    String from,
    String to,
    String Function(String rest) moved,
  ) => {
    for (final MapEntry(:key, :value) in map.entries)
      key.startsWith('$from ')
              ? '$to ${moved(key.substring(from.length + 1))}'
              : key:
          value,
  };

  /// [map] with what is under [from] under [to] instead.
  static Map<String, List<String>> _moved(
    Map<String, List<String>> map,
    String from,
    String to,
  ) => map.containsKey(from)
      ? _with(_with(map, from, const []), to, map[from]!)
      : map;

  /// These prefs with [slug] dropped from the order, from the last chat when it is on [server],
  /// and with its pins, recent chats and the messages waiting in its chats forgotten, as when
  /// the workspace is deleted.
  Prefs withoutWorkspace(String server, String slug) => _copy(
    workspaceOrder: [...workspaceOrder.where((s) => s != slug)],
    lastChat: () => lastChatIn(server, slug) ? null : lastChat,
    pinned: _with(pinned, offKey(server, slug), const []),
    recent: _with(recent, offKey(server, slug), const []),
    onDeck: {
      for (final MapEntry(:key, :value) in onDeck.entries)
        if (!key.startsWith('${offKey(server, slug)} ')) key: value,
    },
  );

  /// These prefs with chat [thread] of workspace [slug] on [server] as the last on screen; a
  /// null [thread] is a draft.
  Prefs withLastChat(String server, String slug, String? thread) =>
      _copy(lastChat: () => LastChat(slug, thread, server));

  Prefs withTheme(ThemePref theme) => _copy(theme: theme);

  Prefs withTextSize(TextSize size) => _copy(textSize: size);

  Prefs withSwitch(ChatSwitch which, bool on) =>
      _copy(switches: {...switches, which: on});

  Prefs withShortcuts(List<PromptShortcut> shortcuts) =>
      _copy(shortcuts: List.unmodifiable(shortcuts));

  Prefs withShortcutUse(String key, ShortcutUse use) {
    final next = {...shortcutUses, key: use};
    if (next.length > shortcutUsesMax) {
      next.remove(next.keys.first);
    }
    return _copy(shortcutUses: next);
  }

  String encode() => jsonEncode({
    'workspaceOrder': workspaceOrder,
    'theme': theme.name,
    'textSize': textSize.name,
    if (lastChat != null) 'lastChat': lastChat!.toJson(),
    'chat': {
      for (final MapEntry(:key, :value) in switches.entries) key.name: value,
    },
    if (pinned.isNotEmpty) 'pinned': pinned,
    if (recent.isNotEmpty) 'recent': recent,
    if (shortcuts.isNotEmpty)
      'shortcuts': [for (final shortcut in shortcuts) shortcut.toJson()],
    if (shortcutUses.isNotEmpty)
      'shortcutUses': {
        for (final entry in shortcutUses.entries)
          entry.key: entry.value.toJson(),
      },
    if (onDeck.isNotEmpty)
      'onDeck': {
        for (final entry in onDeck.entries)
          entry.key: [for (final m in entry.value) m.toJson()],
      },
    if (users.isNotEmpty)
      'users': {
        for (final MapEntry(:key, :value) in users.entries) key: value.toJson(),
      },
    if (lastFolders.isNotEmpty) 'lastFolders': lastFolders,
  });

  /// Reads what [encode] wrote. Anything it cannot read falls back to the default, and keys it
  /// no longer uses, such as the old `groundedOnly` and `switchedOff`, are ignored.
  static Prefs decode(String text) {
    final json = jsonOrNull(text);
    if (json is! Map) return const Prefs();
    final order = json['workspaceOrder'];
    final folders = json['lastFolders'];
    final chat = json['chat'];
    final switchNamed = ChatSwitch.values.asNameMap();
    return Prefs(
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
      shortcuts: [
        if (json['shortcuts'] is List)
          for (final item in json['shortcuts'] as List)
            ?PromptShortcut.fromJson(item),
      ],
      shortcutUses: _shortcutUsesOf(json['shortcutUses']),
      onDeck: _onDeckOf(json['onDeck']),
      users: _usersOf(json['users']),
      lastFolders: {
        if (folders is Map)
          for (final MapEntry(:key, :value) in folders.entries)
            if (key is String && value is String && value.isNotEmpty)
              key: value,
      },
    );
  }

  /// Each server's chosen user in [json], as [users] is written.
  static Map<String, ServerUser> _usersOf(Object? json) => {
    if (json is Map)
      for (final MapEntry(:key, :value) in json.entries)
        if (ServerUser.fromSaved(value) case final user? when key is String)
          key: user,
  };

  /// Each chat's waiting messages in [json], as [onDeck] is written.
  static Map<String, List<SavedOnDeck>> _onDeckOf(Object? json) => {
    if (json is Map)
      for (final MapEntry(:key, :value) in json.entries)
        if (key is String && value is List)
          if ([for (final m in value) ?SavedOnDeck.fromJson(m)]
              case final messages when messages.isNotEmpty)
            key: messages,
  };

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

  static Map<String, ShortcutUse> _shortcutUsesOf(Object? json) {
    if (json is! Map) return const {};
    final uses = <String, ShortcutUse>{};
    for (final entry in json.entries) {
      final use = ShortcutUse.fromJson(entry.value);
      if (entry.key is String && use != null) {
        uses[entry.key as String] = use;
      }
    }
    return uses;
  }
}
