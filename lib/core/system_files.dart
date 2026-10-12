import 'apps.dart';
import 'copy.dart';

/// One entry of a System files folder on the apps server: a folder of [count] entries, or a
/// file of [size] bytes, last changed at [modified] where the server knows. [about] is the
/// server's line about a top-level entry.
class SystemEntry {
  const SystemEntry(
    this.name, {
    required this.folder,
    this.size,
    this.count,
    this.modified,
    this.about = '',
  });

  final String name;
  final bool folder;
  final int? size;
  final int? count;
  final DateTime? modified;
  final String about;

  /// The line under its name: the server's line, then how many entries a folder holds, or a
  /// file's size and when it changed.
  String line(DateTime now) => [
    if (about.isNotEmpty) about,
    if (folder) plural(count ?? 0, 'entry', 'entries'),
    if (!folder) bytesText(size ?? 0),
    if (!folder && modified != null) whenShort(modified!, now),
  ].join(' · ');
}

/// `GET /system/tree`'s entries, folders first, each part by name, as the server sends them.
List<SystemEntry> systemEntriesOf(Object? json) {
  final list = json is Map ? json['entries'] : null;
  return [
    if (list is List)
      for (final entry in list)
        if (entry is Map && entry['name'] is String)
          SystemEntry(
            entry['name'] as String,
            folder: entry['folder'] == true,
            size: entry['size'] is int ? entry['size'] as int : null,
            count: entry['count'] is int ? entry['count'] as int : null,
            modified: fromSeconds(entry['modified']),
            about: entry['about'] is String ? entry['about'] as String : '',
          ),
  ];
}

/// The path of [name] in the folder at [folder], `""` being the top.
String systemPathOf(String folder, String name) =>
    folder.isEmpty ? name : '$folder/$name';

/// What a header names the System files folder or file at [path]: its last name, or System
/// files for the top.
String systemTitle(String path) =>
    path.isEmpty ? 'System files' : path.split('/').last;
