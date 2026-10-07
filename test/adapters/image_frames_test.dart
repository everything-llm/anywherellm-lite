import 'dart:convert';

import 'package:anywherellm/adapters/image_frames.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:flutter_test/flutter_test.dart';

const _live = 'multipart/x-mixed-replace; boundary=frame';

/// A live image's body as everythingllm's `chatimage.live` pushes it: each of [frames] as a
/// part with its own `Content-Length` unless [lengths] is false, then the closing delimiter
/// when [closed].
List<int> _multipart(
  List<String> frames, {
  bool lengths = true,
  bool closed = true,
}) => [
  for (final frame in frames) ...[
    ...ascii.encode('--frame\r\nContent-Type: image/png\r\n'),
    if (lengths) ...ascii.encode('Content-Length: ${frame.length}\r\n'),
    ...ascii.encode('\r\n$frame\r\n'),
  ],
  if (closed) ...ascii.encode('--frame--\r\n'),
];

Future<List<String>> _frames(
  Stream<List<int>> body,
  String? type, {
  int limit = maxImageBytes,
}) async => [
  for (final frame in await imageFrames(body, type, limit: limit).toList())
    ascii.decode(frame),
];

/// [bytes] arriving one at a time, so every delimiter and header straddles chunks.
Stream<List<int>> _byteByByte(List<int> bytes) => Stream.fromIterable([
  for (final b in bytes) [b],
]);

void main() {
  test('each part of a live image is a frame', () async {
    final body = _multipart(['first', 'second']);
    expect(await _frames(Stream.value(body), _live), ['first', 'second']);
    expect(await _frames(_byteByByte(body), _live), ['first', 'second']);
  });

  test(
    'a part is read to its length, even when it holds the delimiter',
    () async {
      final body = _multipart(['a\r\n--frame--\r\nb', 'c']);
      expect(await _frames(_byteByByte(body), _live), [
        'a\r\n--frame--\r\nb',
        'c',
      ]);
    },
  );

  test('a part with no length is cut at the next delimiter', () async {
    final body = _multipart(['first', 'second'], lengths: false);
    expect(await _frames(_byteByByte(body), _live), ['first', 'second']);
  });

  test('the closing delimiter ends the image', () async {
    final body = [
      ..._multipart(['first']),
      ..._multipart(['late']),
    ];
    expect(await _frames(Stream.value(body), _live), ['first']);
  });

  test('a body that ends without closing keeps the frames it gave', () async {
    final body = _multipart(['first', 'second'], closed: false);
    expect(await _frames(Stream.value(body), _live), ['first', 'second']);
  });

  test('a quoted boundary and its case are read', () async {
    final body = _multipart(['first']);
    expect(
      await _frames(
        Stream.value(body),
        'Multipart/X-Mixed-Replace; charset=x; Boundary="frame"',
      ),
      ['first'],
    );
  });

  test('a plain image is one frame, however it arrives', () async {
    final body = ascii.encode('a whole png');
    expect(await _frames(_byteByByte(body), 'image/png'), ['a whole png']);
    expect(await _frames(Stream.value(body), null), ['a whole png']);
    expect(await _frames(const Stream.empty(), 'image/png'), isEmpty);
  });

  test('an image past the limit fails', () async {
    expect(
      _frames(Stream.value(ascii.encode('too long')), 'image/png', limit: 4),
      throwsA(isA<ApiException>()),
    );
    expect(
      _frames(Stream.value(_multipart(['too long'])), _live, limit: 4),
      throwsA(isA<ApiException>()),
    );
    expect(
      _frames(
        _byteByByte(_multipart(['x' * 5000], lengths: false)),
        _live,
        limit: 4,
      ),
      throwsA(isA<ApiException>()),
    );
  });
}
