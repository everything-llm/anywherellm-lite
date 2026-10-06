import 'dart:io';

import '../core/ports.dart';
import '../core/prefs.dart';

/// [PrefsStore] in one JSON file, `anywherellm/prefs.json` under `$XDG_CONFIG_HOME` or `~/.config`.
/// Holds nothing secret: the key stays in the keyring.
class JsonPrefsStore implements PrefsStore {
  JsonPrefsStore([File? file]) : _file = file ?? _defaultFile();

  final File _file;

  /// The last write, which the next one waits for, so writes land in the order they were asked.
  Future<void> _last = Future.value();

  static File _defaultFile() {
    final env = Platform.environment;
    final config = switch (env['XDG_CONFIG_HOME']) {
      final String dir when dir.isNotEmpty => dir,
      _ => '${env['HOME'] ?? '.'}/.config',
    };
    return File('$config/anywherellm/prefs.json');
  }

  @override
  Future<Prefs> load() async {
    try {
      return Prefs.decode(await _file.readAsString());
    } on FileSystemException {
      return const Prefs();
    }
  }

  /// Writes beside the file and renames over it, so a crash never leaves half a file.
  @override
  Future<void> save(Prefs prefs) {
    final write = _last.then((_) => _write(prefs));
    _last = write.catchError((_) {});
    return write;
  }

  Future<void> _write(Prefs prefs) async {
    try {
      await _file.parent.create(recursive: true);
      final temp = File('${_file.path}.tmp');
      await temp.writeAsString(prefs.encode(), flush: true);
      await temp.rename(_file.path);
    } on FileSystemException catch (error) {
      throw ApiException(
        'Could not save the app\'s preferences to ${_file.path}: ${error.message}',
      );
    }
  }
}
