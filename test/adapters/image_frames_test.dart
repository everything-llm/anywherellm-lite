import 'dart:convert';

import 'package:anywherellm/adapters/image_frames.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/multipart.dart';

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
    final body = multipart(['first', 'second']);
    expect(await _frames(Stream.value(body), multipartType), [
      'first',
      'second',
    ]);
    expect(await _frames(_byteByByte(body), multipartType), [
      'first',
      'second',
    ]);
  });

  test(
    'a part is read to its length, even when it holds the delimiter',
    () async {
      final body = multipart(['a\r\n--frame--\r\nb', 'c']);
      expect(await _frames(_byteByByte(body), multipartType), [
        'a\r\n--frame--\r\nb',
        'c',
      ]);
    },
  );

  test('the closing delimiter ends the image', () async {
    final body = [
      ...multipart(['first']),
      ...multipart(['late']),
    ];
    expect(await _frames(Stream.value(body), multipartType), ['first']);
  });

  test('a body that ends without closing keeps the frames it gave', () async {
    final body = multipart(['first', 'second'], closed: false);
    expect(await _frames(Stream.value(body), multipartType), [
      'first',
      'second',
    ]);
  });

  test('a quoted boundary and its case are read', () async {
    expect(
      await _frames(
        Stream.value(multipart(['first'])),
        'Multipart/X-Mixed-Replace; charset=x; Boundary="frame"',
      ),
      ['first'],
    );
  });

  test('a part with no length fails', () async {
    final body = multipart(['first'], lengths: false);
    expect(
      _frames(Stream.value(body), multipartType),
      throwsA(isA<ApiException>()),
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
      _frames(Stream.value(multipart(['too long'])), multipartType, limit: 4),
      throwsA(isA<ApiException>()),
    );
  });
}
