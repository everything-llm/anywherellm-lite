/// A companion server: one that may run beside AnythingLLM, takes the same developer key, and
/// says what it is at `GET /health` under `service`. It runs where it was said to, or else on its
/// own [port] of the AnythingLLM host over https ([base]). The app works without any, and shows
/// what one adds only while it answers.
class Companion {
  const Companion({
    required this.service,
    required this.port,
    required this.name,
    required this.code,
  });

  /// What its `/health` names itself, as `anythingllm-toolkit`.
  final String service;
  final int port;

  /// What a pairing code names its address by, as `toolkit` in `&toolkit=...`.
  final String code;

  /// How a message names it, as `The toolkit`.
  final String name;

  /// Its address beside the AnythingLLM server at [server]: the same host on [port].
  Uri base(Uri server) => Uri(scheme: 'https', host: server.host, port: port);

  /// Whether [json], an answer to `GET /health`, is this companion's.
  bool isHealth(Object? json) => json is Map && json['service'] == service;
}

/// The parts of [uri]'s path, without empty ones.
List<String> segmentsOf(Uri uri) => [
  for (final part in uri.pathSegments)
    if (part.isNotEmpty) part,
];

/// [path] under [base]'s own path, with [query]: how a companion behind a path prefix, as
/// `https://host/apps`, is reached.
Uri under(Uri base, List<String> path, [Map<String, String>? query]) =>
    base.replace(
      pathSegments: [...segmentsOf(base), ...path],
      queryParameters: query == null || query.isEmpty ? null : query,
    );
