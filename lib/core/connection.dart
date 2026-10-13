import 'apps.dart';
import 'errors.dart';
import 'toolkit.dart';

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

  /// Whether the key travels unencrypted: a plain http address, on a private network.
  bool get plainHttp => uri.scheme == 'http';

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

  /// Where each companion runs, by [Companion.service], when the person or a pairing code said;
  /// a companion not named here is where [Companion.base] guesses.
  Map<String, Uri> companions = const {};

  /// Where [companion] runs beside the server in use: where it was said to, or else
  /// [Companion.base]'s guess. Null with no server.
  Uri? addressOf(Companion companion) => switch (current) {
    final server? =>
      companions[companion.service] ?? companion.base(server.uri),
    null => null,
  };
}

/// The address as the client wants it: trimmed, https or, on a private network ([keySafe]),
/// http, no trailing slash, no `/api`. Throws [ApiException] saying what is wrong with [raw].
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
  if (!keySafe(uri)) throw const ApiException(plainHttpRefused);
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

/// A connection and where each of its companions runs when that was said, by
/// [Companion.service]: what a pairing code carries, and what the keyring keeps.
class Pairing {
  const Pairing(this.connection, [this.companions = const {}]);

  final Connection connection;
  final Map<String, Uri> companions;
}

/// What an AnywhereLLM pairing code carries, checked as [Connection.parse] checks a typed
/// connection. The code is `anywherellm://connect?url=...&key=...`, both values
/// percent-encoded, and may name companions' addresses by service after them, as
/// `toolkit=...&apps=...` by each one's [Companion.code]. Throws [ApiException] when [raw] is not a
/// pairing code or what it carries cannot be used.
Pairing parsePairingCode(String raw) {
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
  return Pairing(Connection.parse(url, key), {
    for (final companion in const [appsCompanion, toolkitCompanion])
      if (uri.queryParameters[companion.code] case final address?)
        companion.service: _companionAddress(address),
  });
}

/// A companion's address as a pairing code gives it, cleaned as [normalizeBaseUrl] cleans the server's:
/// https, or http on a private network, with no query, no fragment and no trailing slash.
Uri _companionAddress(String raw) => Uri.parse(normalizeBaseUrl(raw));

/// Why a plain http address is refused.
const plainHttpRefused =
    'Use an https:// address. Plain http works only on a private network: at home, on '
    'Tailscale or on this device, since the key travels unencrypted.';

/// Whether the key may go to [uri]: over https, or over http to a private host
/// ([isPrivateHost]).
bool keySafe(Uri uri) =>
    uri.scheme == 'https' || (uri.scheme == 'http' && isPrivateHost(uri.host));

/// Whether [host] is on a private network: this device, a home network or Tailscale. That is
/// `localhost`, a name with no dot (a home network's, such as `nas`), a name under `.local`,
/// `.lan`, `.home.arpa` or `.ts.net`, an IPv4 address in `127/8`, `10/8`, `172.16/12`,
/// `192.168/16`, `169.254/16` or `100.64/10` (Tailscale's), or an IPv6 address that is `::1`,
/// unique-local (`fc00::/7`) or link-local (`fe80::/10`).
bool isPrivateHost(String host) {
  final name = host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  if (isLoopback(name)) return true;
  if (name.contains(':')) {
    final v6 = name.replaceAll(RegExp(r'^\[|\]$'), '');
    return RegExp(r'^f[cd][0-9a-f]{0,2}:').hasMatch(v6) ||
        RegExp(r'^fe[89ab][0-9a-f]?:').hasMatch(v6);
  }
  final parts = name.split('.');
  final octets = [for (final part in parts) int.tryParse(part)];
  if (parts.length == 4 &&
      octets.every((o) => o != null && o >= 0 && o <= 255)) {
    final [a, b, _, _] = [for (final o in octets) o!];
    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 169 && b == 254) ||
        (a == 100 && b >= 64 && b <= 127);
  }
  return !name.contains('.') ||
      const ['.local', '.lan', '.home.arpa', '.ts.net'].any(name.endsWith);
}

/// Whether [host] names the machine it is used on: `localhost`, `127.x.x.x`, `::1` or
/// `0.0.0.0`.
bool isLoopback(String host) =>
    host == 'localhost' ||
    host.startsWith('127.') ||
    host == '::1' ||
    host == '0.0.0.0';
