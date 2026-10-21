import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/errors.dart';

/// [error], from sending a request to [name] that may take [limit], in plain words. [name] is
/// what was asked, as `The server` or `The toolkit`, and [where] what a failed connection names,
/// as its host. An error of any other kind gets a fixed message with no error text, since a
/// header the platform refused is quoted in it, key and all.
ApiException unreachable(
  Exception error, {
  required String name,
  required String where,
  required Duration limit,
}) {
  final lower = '${name[0].toLowerCase()}${name.substring(1)}';
  return switch (error) {
    TimeoutException() => ApiException(
      '$name did not answer within ${durationText(limit)}.',
    ),
    HandshakeException() => ApiException(
      '$name\'s certificate could not be verified.',
    ),
    // Before [http.ClientException], which a socket's failure may also be.
    SocketException(:final message) => ApiException(
      'Could not reach $where: $message',
    ),
    http.ClientException(:final message) => ApiException(
      'Could not reach $lower: $message',
    ),
    _ => ApiException('Could not reach $lower.'),
  };
}

/// [limit] in words: `15 seconds`, or `5 minutes` from two minutes up.
String durationText(Duration limit) => limit.inSeconds < 120
    ? '${limit.inSeconds} seconds'
    : '${limit.inMinutes} minutes';
