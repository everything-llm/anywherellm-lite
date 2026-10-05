import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/connection.dart';
import '../core/ports.dart';

/// [AnythingLlmApi] over the server's HTTP API, with the bearer key on every request.
///
/// An error message never contains the key.
class HttpAnythingLlmApi implements AnythingLlmApi {
  HttpAnythingLlmApi({
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  @override
  Future<void> verify(Connection connection) async {
    final body = await _get(connection, '/api/v1/auth');
    if (body is! Map || body['authenticated'] != true) {
      throw const ApiException('The server did not accept the key.');
    }
  }

  /// The decoded JSON of a GET to [path] on [connection].
  Future<Object?> _get(Connection connection, String path) async {
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('${connection.baseUrl}$path'),
            headers: {
              'Authorization': 'Bearer ${connection.apiKey}',
              'Accept': 'application/json',
            },
          )
          .timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        'The server did not answer within ${timeout.inSeconds} seconds.',
      );
    } on HandshakeException {
      throw const ApiException(
        'The server\'s certificate could not be verified.',
      );
    } on SocketException catch (error) {
      throw ApiException(
        'Could not reach ${connection.host}: ${error.message}',
      );
    } on http.ClientException catch (error) {
      throw ApiException('Could not reach the server: ${error.message}');
    }
    return _decode(response);
  }

  Object? _decode(http.Response response) {
    final status = response.statusCode;
    final body = _json(response);
    if (status == 401 || status == 403) {
      throw ApiException('The server rejected the key.', status: status);
    }
    if (status < 200 || status >= 300) {
      throw ApiException(
        _said(body) ?? 'The server answered HTTP $status.',
        status: status,
      );
    }
    if (body == null) {
      throw ApiException(
        'The address did not answer like an AnythingLLM server.',
        status: status,
      );
    }
    return body;
  }

  /// The decoded JSON of [response], or null when it is not JSON.
  Object? _json(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  /// The `error` or `message` the server put in a failed response, when it did.
  String? _said(Object? body) {
    if (body is! Map) return null;
    final said = body['error'] ?? body['message'];
    return said is String && said.trim().isNotEmpty ? said.trim() : null;
  }
}
