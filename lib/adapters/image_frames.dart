import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../core/ports.dart';

/// The most bytes one image, or one frame of a live image, may take.
const maxImageBytes = 16 * 1024 * 1024;

/// The images in a response [body] whose `Content-Type` is [contentType]: each part of a
/// `multipart/x-mixed-replace` response as it arrives, as a live image is pushed; otherwise the
/// whole body as one image. Fails with [ApiException] when an image passes [limit] bytes.
///
/// Cancelling cancels [body] at once, which closes the connection. An `async*` reader would
/// only notice at its next `yield`, holding a live image open until its next frame.
Stream<Uint8List> imageFrames(
  Stream<List<int>> body,
  String? contentType, {
  int limit = maxImageBytes,
}) {
  final boundary = _boundary(contentType);
  final reader = boundary == null
      ? _WholeReader(limit)
      : _PartReader(ascii.encode('--$boundary'), limit);
  late final StreamController<Uint8List> out;
  StreamSubscription<List<int>>? source;

  void finish([Object? error]) {
    unawaited(source?.cancel());
    source = null;
    if (error != null) out.addError(error);
    unawaited(out.close());
  }

  out = StreamController(
    onListen: () => source = body.listen(
      (chunk) {
        try {
          if (reader.add(chunk, out.add)) finish();
        } on ApiException catch (error) {
          finish(error);
        }
      },
      onError: (Object error) => finish(error),
      onDone: () {
        source = null;
        reader.end(out.add);
        unawaited(out.close());
      },
    ),
    onPause: () => source?.pause(),
    onResume: () => source?.resume(),
    onCancel: () => source?.cancel(),
  );
  return out.stream;
}

/// The `boundary` of a `multipart/x-mixed-replace` [contentType], or null for any other type.
String? _boundary(String? contentType) {
  if (contentType == null) return null;
  final [type, ...params] = contentType.split(';');
  if (type.trim().toLowerCase() != 'multipart/x-mixed-replace') return null;
  for (final param in params) {
    final [name, ...value] = param.split('=');
    if (name.trim().toLowerCase() != 'boundary' || value.isEmpty) continue;
    final boundary = value.join('=').trim().replaceAll('"', '');
    if (boundary.isNotEmpty) return boundary;
  }
  return null;
}

/// Reads a body a chunk at a time, giving each image it finds to `emit`.
sealed class _Reader {
  /// Reads [chunk]; true when the body says it has ended.
  bool add(List<int> chunk, void Function(Uint8List) emit);

  /// Gives what is left once the body ends.
  void end(void Function(Uint8List) emit) {}
}

/// The whole body as one image.
final class _WholeReader extends _Reader {
  _WholeReader(this.limit);

  final int limit;
  final _bytes = BytesBuilder(copy: false);

  @override
  bool add(List<int> chunk, void Function(Uint8List) emit) {
    _bytes.add(chunk);
    if (_bytes.length > limit) throw _tooBig;
    return false;
  }

  @override
  void end(void Function(Uint8List) emit) {
    if (_bytes.isNotEmpty) emit(_bytes.takeBytes());
  }
}

/// Each part's body between the [delimiter] lines (`--boundary`), read to its `Content-Length`
/// when it gives one and otherwise to the next delimiter, until the closing `--boundary--`.
final class _PartReader extends _Reader {
  _PartReader(this.delimiter, this.limit);

  final Uint8List delimiter;
  final int limit;

  /// What has come since the last part ended, so a delimiter is looked for from its start.
  final _buffer = _Buffer();

  @override
  bool add(List<int> chunk, void Function(Uint8List) emit) {
    final buffer = _buffer..add(chunk);
    while (true) {
      final start = buffer.indexOf(delimiter, 0);
      if (start < 0) break;
      final after = start + delimiter.length;
      if (buffer.length < after + 2) break;
      if (buffer[after] == _dash && buffer[after + 1] == _dash) return true;
      final line = buffer.indexOf(_crlf, after);
      if (line < 0) break;
      // The headers end at the first empty line, which a part without headers starts with.
      final headersEnd = buffer.indexOf(_blankLine, line);
      if (headersEnd < 0) break;
      final from = headersEnd + _blankLine.length;
      final length = _contentLength(buffer.text(line + 2, headersEnd));
      if (length != null && length > limit) throw _tooBig;
      final end = length != null
          ? from + length
          : buffer.indexOf(_nextDelimiter(delimiter), from);
      if (end < 0 || buffer.length < end) break;
      emit(buffer.take(from, end));
      buffer.drop(end);
    }
    if (buffer.length > limit + 4096) throw _tooBig;
    return false;
  }
}

/// The `Content-Length` among a part's [headers], or null when it has none it can read.
int? _contentLength(String headers) {
  for (final line in const LineSplitter().convert(headers)) {
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    if (line.substring(0, colon).trim().toLowerCase() != 'content-length') {
      continue;
    }
    return int.tryParse(line.substring(colon + 1).trim());
  }
  return null;
}

Uint8List _nextDelimiter(Uint8List delimiter) =>
    Uint8List.fromList([..._crlf, ...delimiter]);

const _dash = 0x2d;
final _crlf = Uint8List.fromList([13, 10]);
final _blankLine = Uint8List.fromList([13, 10, 13, 10]);
const _tooBig = ApiException('The image is too large to show.');

/// Bytes received and not yet read, growing as chunks come.
class _Buffer {
  Uint8List _data = Uint8List(64 * 1024);
  int _length = 0;

  int get length => _length;

  int operator [](int i) => _data[i];

  void add(List<int> chunk) {
    if (_length + chunk.length > _data.length) {
      var size = _data.length;
      while (size < _length + chunk.length) {
        size *= 2;
      }
      _data = Uint8List(size)..setRange(0, _length, _data);
    }
    _data.setRange(_length, _length + chunk.length, chunk);
    _length += chunk.length;
  }

  /// Where [pattern] first starts at or after [from], or -1.
  int indexOf(Uint8List pattern, int from) {
    final last = _length - pattern.length;
    outer:
    for (var i = from < 0 ? 0 : from; i <= last; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (_data[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  String text(int from, int to) =>
      latin1.decode(Uint8List.sublistView(_data, from, to));

  /// A copy of the bytes from [from] to [to].
  Uint8List take(int from, int to) =>
      Uint8List.fromList(Uint8List.sublistView(_data, from, to));

  /// Forgets the bytes before [end].
  void drop(int end) {
    _data.setRange(0, _length - end, _data, end);
    _length -= end;
  }
}
