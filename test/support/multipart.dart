import 'dart:convert';

/// A live image's body as everythingllm's `chatimage.live` pushes it: each of [frames] as a
/// part with its own `Content-Length` unless [lengths] is false, then the closing delimiter
/// when [closed].
List<int> multipart(
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

/// The `Content-Type` of a body [multipart] makes.
const multipartType = 'multipart/x-mixed-replace; boundary=frame';
