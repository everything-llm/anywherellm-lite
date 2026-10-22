/// A companion server: one that may run beside AnythingLLM, takes the same developer key, and
/// says what it is at `GET /health` under `service`. It runs where a pairing code said it does,
/// and without one under its [path] on the server's own origin, where a proxy in front of
/// AnythingLLM may route it. The app works without any, and shows what one adds only while it
/// answers.
class Companion {
  const Companion({
    required this.service,
    required this.name,
    required this.code,
    this.formerly = const [],
    this.path,
  });

  /// What its `/health` names itself, as `anywherellm-bridge`.
  final String service;

  /// What an older version's `/health` named it, which is still taken as this companion.
  final List<String> formerly;

  /// Every name its `/health` may give: its [service], then those it had [formerly].
  List<String> get names => [service, ...formerly];

  /// What a pairing code names its address by, as `toolkit` in `&toolkit=...`, and what the
  /// app keeps that address under.
  final String code;

  /// How a message names it, as `The toolkit`.
  final String name;

  /// The path it is looked for under on the server's own origin when no pairing code said where
  /// it runs, as `anywherellm-bridge`, or null for none.
  final String? path;

  /// Where it runs on [server]'s own origin, its scheme, host and port, under [path], or null
  /// without one. The key already goes to that origin, so asking there hands it to no one new;
  /// another host or port could be anyone's.
  Uri? onOrigin(Uri server) => switch (path) {
    final path? => Uri(
      scheme: server.scheme,
      host: server.host,
      port: server.hasPort ? server.port : null,
      pathSegments: [path],
    ),
    null => null,
  };

  /// Whether [json], an answer to `GET /health`, is this companion's, under any of its [names].
  bool isHealth(Object? json) => json is Map && names.contains(json['service']);
}

/// The parts of [uri]'s path, without empty ones.
List<String> segmentsOf(Uri uri) => [
  for (final part in uri.pathSegments)
    if (part.isNotEmpty) part,
];

/// [path] under [base]'s own path, with [query]: how a companion behind a path prefix, as
/// `https://host/toolkit`, is reached.
Uri under(Uri base, List<String> path, [Map<String, String>? query]) =>
    base.replace(
      pathSegments: [...segmentsOf(base), ...path],
      queryParameters: query == null || query.isEmpty ? null : query,
    );
