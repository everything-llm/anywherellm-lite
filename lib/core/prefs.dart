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

class Prefs {
  const Prefs({this.switchedOff = const {}});

  /// The documents switched off in each workspace, by its slug.
  final Map<String, List<OffDoc>> switchedOff;

  List<OffDoc> offIn(String slug) => switchedOff[slug] ?? const [];

  /// These prefs with [slug]'s switched-off documents set to [docs].
  Prefs withOff(String slug, List<OffDoc> docs) => Prefs(
    switchedOff: {
      for (final entry in switchedOff.entries)
        if (entry.key != slug) entry.key: entry.value,
      if (docs.isNotEmpty) slug: docs,
    },
  );

  /// These prefs with the documents at [paths] forgotten in every workspace.
  Prefs withoutDocs(Set<String> paths) => Prefs(
    switchedOff: {
      for (final MapEntry(:key, :value) in switchedOff.entries)
        if (value.where((d) => !paths.contains(d.path)).toList() case final kept
            when kept.isNotEmpty)
          key: kept,
    },
  );

  String encode() => jsonEncode({
    'switchedOff': {
      for (final entry in switchedOff.entries)
        entry.key: [for (final doc in entry.value) doc.toJson()],
    },
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
    return Prefs(
      switchedOff: {
        if (off is Map)
          for (final entry in off.entries)
            if (entry.key is String && entry.value is List)
              entry.key as String: [
                for (final doc in entry.value as List) ?OffDoc.fromJson(doc),
              ],
      },
    );
  }
}
