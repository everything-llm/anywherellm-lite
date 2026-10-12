import 'dart:io';

import '../core/ports.dart';
import '../core/prefs.dart';

/// [PrefsStore] in one JSON [File], `prefs.json` in the app's private storage. Holds nothing
/// secret: the key stays in the keyring.
class JsonPrefsStore implements PrefsStore {
  JsonPrefsStore(this._file);

  final File _file;

  /// The prefs to write next, while a write runs: only the newest is written, since each holds
  /// everything.
  Prefs? _pending;

  /// The writes under way, which a save meanwhile joins.
  Future<void>? _writing;

  /// Whether the file's folder is known to exist.
  bool _folder = false;

  @override
  Future<Prefs> load() async {
    try {
      return Prefs.decode(await _file.readAsString());
    } on FileSystemException {
      return const Prefs();
    }
  }

  /// Writes beside the file and renames over it, so a crash never leaves half a file. A save
  /// made while another writes waits for it and writes only the newest prefs saved meanwhile;
  /// each save's future ends when what it asked is on disk, or fails with the last write's
  /// failure.
  @override
  Future<void> save(Prefs prefs) {
    _pending = prefs;
    return _writing ??= _drain();
  }

  Future<void> _drain() async {
    try {
      ApiException? failed;
      for (var next = _pending; next != null; next = _pending) {
        _pending = null;
        try {
          await _write(next);
          failed = null;
        } on ApiException catch (error) {
          failed = error;
        }
      }
      if (failed != null) throw failed;
    } finally {
      _writing = null;
    }
  }

  Future<void> _write(Prefs prefs) async {
    try {
      if (!_folder) {
        await _file.parent.create(recursive: true);
        _folder = true;
      }
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
