import 'errors.dart';

/// Where an AnythingLLM server is, the key that opens its developer API, and the password that
/// signs in to its web UI's own routes when the server has one.
class Connection {
  const Connection({
    required this.baseUrl,
    required this.apiKey,
    this.password,
  });

  /// The connection [url] and [key] describe, with the address cleaned by [normalizeBaseUrl].
  /// An empty [password] is none. Throws [ApiException] saying what is wrong with them.
  factory Connection.parse(String url, String key, {String? password}) {
    final baseUrl = normalizeBaseUrl(url);
    final apiKey = key.trim();
    if (apiKey.isEmpty) throw const ApiException('Enter the API key.');
    return Connection(baseUrl: baseUrl, apiKey: apiKey).withPassword(password);
  }

  /// `https://host:port`, with no trailing slash and no `/api`. See [normalizeBaseUrl].
  final String baseUrl;
  final String apiKey;

  /// The server's password, or null when none is saved. Kept as typed: a password may begin or
  /// end with a space.
  final String? password;

  /// This connection with [password] in place of its own; an empty one is none.
  Connection withPassword(String? password) => Connection(
    baseUrl: baseUrl,
    apiKey: apiKey,
    password: password == null || password.isEmpty ? null : password,
  );

  /// [baseUrl] parsed.
  Uri get uri => Uri.parse(baseUrl);

  /// The server's host name, for messages.
  String get host => uri.host;

  @override
  bool operator ==(Object other) =>
      other is Connection &&
      other.baseUrl == baseUrl &&
      other.apiKey == apiKey &&
      other.password == password;

  @override
  int get hashCode => Object.hash(baseUrl, apiKey, password);

  /// Never prints the key or the password, so a log line or a failed assertion cannot leak them.
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

/// The text a QR code carries to hand [connection] to another device:
/// `anywherellm://connect?url=...&key=...`, with both values percent-encoded. The password
/// stays behind: each device signs in for itself.
String pairingCode(Connection connection) => Uri(
  scheme: 'anywherellm',
  host: 'connect',
  queryParameters: {'url': connection.baseUrl, 'key': connection.apiKey},
).toString();

/// The connection a [pairingCode] carries, checked as [Connection.parse] checks a typed one.
/// Throws [ApiException] when [raw] is not a pairing code or what it carries cannot be used.
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

/// Why a phone cannot use [connection]'s [pairingCode], or null when it can.
String? pairingProblem(Connection connection) {
  final host = connection.host;
  final loopback =
      host == 'localhost' ||
      host.startsWith('127.') ||
      host == '::1' ||
      host == '0.0.0.0';
  if (loopback) {
    return 'On the phone, $host is the phone itself. Use an address the phone can reach, '
        "such as the server's Tailscale name.";
  }
  if (connection.uri.scheme == 'http') {
    return 'AnywhereLLM on Android connects only over https.';
  }
  return null;
}
