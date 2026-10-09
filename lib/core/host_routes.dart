/// The port the everythingllm host serves its live cards and client routes on: the machine's own
/// route for `/_live`.
const cardsPort = 8445;

/// A route under `/_live` on the [server]'s host, as `browser/chat/q3/budget`, with [query].
Uri liveRoute(Uri server, String path, [Map<String, String>? query]) => server
    .replace(port: cardsPort, path: '/_live/$path', queryParameters: query);
