import 'errors.dart';

/// Where an AnythingLLM server is, and the developer key that opens its developer API, the one
/// way the app reaches it.
class Connection {
  const Connection({required this.baseUrl, required this.apiKey});

  /// The connection [url] and [key] describe, with the address cleaned by [normalizeBaseUrl].
  /// Throws [ApiException] saying what is wrong with them.
  factory Connection.parse(String url, String key) {
    final baseUrl = normalizeBaseUrl(url);
    final apiKey = key.trim();
    if (apiKey.isEmpty) throw const ApiException('Enter the API key.');
    return Connection(baseUrl: baseUrl, apiKey: apiKey);
  }

  /// `https://host:port`, with no trailing slash and no `/api`. See [normalizeBaseUrl].
  final String baseUrl;
  final String apiKey;

  /// [baseUrl] parsed.
  Uri get uri => Uri.parse(baseUrl);

  /// The server's host name, for messages.
  String get host => uri.host;

  @override
  bool operator ==(Object other) =>
      other is Connection && other.baseUrl == baseUrl && other.apiKey == apiKey;

  @override
  int get hashCode => Object.hash(baseUrl, apiKey);

  /// Never prints the key, so a log line or a failed assertion cannot leak it.
  @override
  String toString() => 'Connection($baseUrl)';
}

/// The connection in use, or null before one is set up. Settings changes it and the client reads
/// it on every call, so a saved connection is used at once.
class ConnectionHolder {
  ConnectionHolder([this.current]);

  Connection? current;
}

/// The address as the client wants it: trimmed, http or https, no trailing slash, no `/api`.
/// Throws [ApiException] saying what is wrong with [raw].
String normalizeBaseUrl(String raw) {
  final text = raw.trim();
  if (text.isEmpty) throw const ApiException('Enter the server address.');
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty) {
    throw const ApiException(
      'The address must start with http:// or https:// and name a host, '
      'for example https://host.example.ts.net:3001.',
    );
  }
  if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) {
    throw const ApiException(
      'The address must not contain a query, a fragment or a login.',
    );
  }
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  return uri
      .replace(
        path: path.endsWith('/api') ? path.substring(0, path.length - 4) : path,
      )
      .toString();
}

/// The connection an AnywhereLLM pairing code carries, checked as [Connection.parse] checks a
/// typed one. The code is `anywherellm://connect?url=...&key=...`, with both values
/// percent-encoded. Throws [ApiException]
/// when [raw] is not a pairing code or what it carries cannot be used.
Connection parsePairingCode(String raw) {
  const notOurs = ApiException(
    'This QR code is not an AnywhereLLM connection.',
  );
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme != 'anywherellm' || uri.host != 'connect') {
    throw notOurs;
  }
  final url = uri.queryParameters['url'];
  final key = uri.queryParameters['key'];
  if (url == null || key == null) throw notOurs;
  return Connection.parse(url, key);
}

/// Whether [host] names the machine it is used on: `localhost`, `127.x.x.x`, `::1` or
/// `0.0.0.0`.
bool isLoopback(String host) =>
    host == 'localhost' ||
    host.startsWith('127.') ||
    host == '::1' ||
    host == '0.0.0.0';
