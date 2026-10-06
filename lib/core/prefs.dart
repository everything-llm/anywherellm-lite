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

class Prefs {
  const Prefs({
    this.switchedOff = const {},
    this.workspaceOrder = const [],
    this.theme = ThemePref.system,
    this.textSize = TextSize.normal,
  });

  /// The documents switched off in each workspace, by its slug.
  final Map<String, List<OffDoc>> switchedOff;

  /// The slugs of the workspaces in the order the person arranged them. A workspace not listed
  /// follows the listed ones.
  final List<String> workspaceOrder;

  final ThemePref theme;
  final TextSize textSize;

  List<OffDoc> offIn(String slug) => switchedOff[slug] ?? const [];

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
  }) => Prefs(
    switchedOff: switchedOff ?? this.switchedOff,
    workspaceOrder: workspaceOrder ?? this.workspaceOrder,
    theme: theme ?? this.theme,
    textSize: textSize ?? this.textSize,
  );

  /// These prefs with [slug]'s switched-off documents set to [docs].
  Prefs withOff(String slug, List<OffDoc> docs) => _copy(
    switchedOff: {
      for (final entry in switchedOff.entries)
        if (entry.key != slug) entry.key: entry.value,
      if (docs.isNotEmpty) slug: docs,
    },
  );

  /// These prefs with the documents at [paths] forgotten in every workspace.
  Prefs withoutDocs(Set<String> paths) => _copy(
    switchedOff: {
      for (final MapEntry(:key, :value) in switchedOff.entries)
        if (value.where((d) => !paths.contains(d.path)).toList() case final kept
            when kept.isNotEmpty)
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

  /// These prefs with [from] renamed [to] where it stands in the order, as when a workspace's
  /// slug changes.
  Prefs withRenamedWorkspace(String from, String to) => _copy(
    workspaceOrder: [
      for (final s in workspaceOrder)
        if (s == from) to else if (s != to) s,
    ],
  );

  /// These prefs with [slug] dropped from the order, as when the workspace is deleted.
  Prefs withoutWorkspace(String slug) =>
      _copy(workspaceOrder: [...workspaceOrder.where((s) => s != slug)]);

  Prefs withTheme(ThemePref theme) => _copy(theme: theme);

  Prefs withTextSize(TextSize size) => _copy(textSize: size);

  String encode() => jsonEncode({
    'switchedOff': {
      for (final entry in switchedOff.entries)
        entry.key: [for (final doc in entry.value) doc.toJson()],
    },
    'workspaceOrder': workspaceOrder,
    'theme': theme.name,
    'textSize': textSize.name,
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
    );
  }
}
