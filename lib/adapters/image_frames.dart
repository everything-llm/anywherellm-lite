import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http_parser/http_parser.dart';

import '../core/ports.dart';

/// The most bytes one image, or one frame of a live image, may take.
const maxImageBytes = 16 * 1024 * 1024;

/// The images in a response [body] whose `Content-Type` is [contentType]: each part of a
/// `multipart/x-mixed-replace` response as it arrives, as a live image is pushed; otherwise the
/// whole body as one image. Fails with [ApiException] when an image passes [limit] bytes, or a
/// part has no `Content-Length`.
///
/// Cancelling cancels [body] at once, which closes the connection. An `async*` reader would
/// only notice at its next `yield`, holding a live image open until its next frame.
Stream<Uint8List> imageFrames(
  Stream<List<int>> body,
  String? contentType, {
  int limit = maxImageBytes,
}) {
  final boundary = _boundary(contentType);
  final parts = boundary == null ? null : _PartReader(boundary, limit);
  final whole = BytesBuilder(copy: false);
  late final StreamController<Uint8List> out;
  StreamSubscription<List<int>>? source;

  void finish([Object? error]) {
    unawaited(source?.cancel());
    source = null;
    if (error != null) out.addError(error);
    unawaited(out.close());
  }

  void read(List<int> chunk) {
    try {
      if (parts == null) {
        whole.add(chunk);
        if (whole.length > limit) throw _tooBig;
      } else if (parts.add(chunk, out.add)) {
        finish();
      }
    } on ApiException catch (error) {
      finish(error);
    }
  }

  out = StreamController(
    onListen: () => source = body.listen(
      read,
      onError: finish,
      onDone: () {
        if (whole.isNotEmpty) out.add(whole.takeBytes());
        finish();
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
  try {
    final type = MediaType.parse(contentType);
    if (type.mimeType != 'multipart/x-mixed-replace') return null;
    return type.parameters['boundary'];
  } on FormatException {
    return null;
  }
}

/// The parts of a `multipart/x-mixed-replace` body, a chunk at a time: the delimiter and headers
/// up to each part's blank line, then exactly its `Content-Length` bytes, until `--boundary--`.
final class _PartReader {
  _PartReader(String boundary, this.limit)
    : _closing = ascii.encode('--$boundary--');

  final int limit;
  final List<int> _closing;

  /// What has come since the last part's body: the delimiter line and the headers.
  final _head = <int>[];

  /// The part being read, once its headers are in, and how much of it has come.
  Uint8List? _body;
  int _filled = 0;

  /// Reads [chunk], giving each part's body to [emit]; true once the closing delimiter came.
  bool add(List<int> chunk, void Function(Uint8List) emit) {
    var at = 0;
    while (at < chunk.length) {
      if (_body case final body?) {
        final n = min(body.length - _filled, chunk.length - at);
        body.setRange(_filled, _filled + n, chunk, at);
        _filled += n;
        at += n;
        if (_filled == body.length) {
          emit(body);
          _body = null;
        }
        continue;
      }
      _head.add(chunk[at++]);
      if (_endsWith(_closing)) return true;
      if (_endsWith(_blankLine)) _startBody();
      if (_head.length > 8192) throw _tooBig;
    }
    return false;
  }

  /// Reads the headers held, which end at a blank line, and starts the part's body.
  void _startBody() {
    final length = _contentLength(latin1.decode(_head));
    _head.clear();
    if (length == null || length < 0) {
      throw const ApiException('A live image sent a frame with no length.');
    }
    if (length > limit) throw _tooBig;
    _body = Uint8List(length);
    _filled = 0;
  }

  bool _endsWith(List<int> tail) {
    final start = _head.length - tail.length;
    if (start < 0) return false;
    for (var i = 0; i < tail.length; i++) {
      if (_head[start + i] != tail[i]) return false;
    }
    return true;
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

const _blankLine = [13, 10, 13, 10];
const _tooBig = ApiException('The image is too large to show.');
