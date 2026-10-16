import 'package:flutter/foundation.dart';

import '../../core/outputs.dart';
import '../../core/ports.dart';

/// The bytes answers show or offer: the files an agent made, each read once, and the last
/// [imagesKept] images in answers. [clear] forgets them all, as a new server does.
class AnswerBytes {
  AnswerBytes(this._api, {required this.report});

  final AnythingLlmApi _api;

  /// Shows why a file could not be read.
  final void Function(String title, String text) report;

  /// How many answer images [image] keeps.
  static const imagesKept = 12;

  /// The bytes of each file an agent made, by storage name.
  final Map<String, Future<List<int>?>> _files = {};

  /// The [imagesKept] images read last, by address, oldest first.
  final Map<Uri, _ImageRead> _images = {};

  /// How many times [clear] ran, so a read from before it changes nothing.
  int _clears = 0;

  /// The bytes of [file], which an agent made with an answer, read once; null when they could
  /// not be read, and why goes to [report]. A failed read is tried again next time.
  Future<List<int>?> file(GeneratedFile file) =>
      _files[file.storageName] ??= _readFile(file);

  Future<List<int>?> _readFile(GeneratedFile file) async {
    final clears = _clears;
    try {
      return await _api.generatedFile(file.storageName);
    } on ApiException catch (error) {
      if (clears == _clears) {
        _files.remove(file.storageName);
        report('Could not get ${file.name}', error.message);
      }
      return null;
    }
  }

  /// The bytes of the image at [url] in an answer. Fails with [ApiException], and a failed read
  /// is tried again next time.
  Future<Uint8List> image(Uri url) => _imageRead(url).bytes;

  /// The bytes of the image at [url] when a read of it has already ended, else null.
  Uint8List? imageNow(Uri url) =>
      _images.containsKey(url) ? _imageRead(url).done : null;

  /// The read of the image at [url], started when there is none, and now the newest kept.
  _ImageRead _imageRead(Uri url) {
    final read = _images.remove(url) ?? _ImageRead(url, this);
    _images[url] = read;
    if (_images.length > imagesKept) _images.remove(_images.keys.first);
    return read;
  }

  void clear() {
    _clears++;
    _files.clear();
    _images.clear();
  }
}

/// One read of an answer image: its bytes as they are read, and [done] once they are.
class _ImageRead {
  _ImageRead(Uri url, AnswerBytes owner) {
    bytes = owner._api
        .answerImage(url)
        .then(
          (value) => done = value,
          onError: (Object error, StackTrace stack) {
            if (identical(owner._images[url], this)) owner._images.remove(url);
            Error.throwWithStackTrace(error, stack);
          },
        );
  }

  late final Future<Uint8List> bytes;
  Uint8List? done;
}
