/// A companion server: one that may run beside AnythingLLM on its host, on its own [port], over
/// https, takes the same developer key, and says what it is at `GET /health` under `service`.
/// The app works without any, and shows what one adds only while it answers.
class Companion {
  const Companion({
    required this.service,
    required this.port,
    required this.name,
  });

  /// What its `/health` names itself, as `anythingllm-apps-v2`.
  final String service;
  final int port;

  /// How a message names it, as `The apps server`.
  final String name;

  /// Its address beside the AnythingLLM server at [server]: the same host on [port].
  Uri base(Uri server) => Uri(scheme: 'https', host: server.host, port: port);

  /// Whether [json], an answer to `GET /health`, is this companion's.
  bool isHealth(Object? json) => json is Map && json['service'] == service;
}
