/// Firebase Realtime Database over REST: GET, PUT, DELETE (tutor's
/// `lib/sync/rtdb_client.dart`, trimmed to what the relay needs).
///
/// Every request carries `?auth=<idToken>`, so errors name the method,
/// path and status only, never the URL.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Supplies a currently valid Firebase ID token.
typedef IdTokenSource = Future<String> Function();

/// RTDB's server-time placeholder, resolved on write.
const serverTime = {'.sv': 'timestamp'};

/// A failed RTDB request. [status] is null for network failures.
class RtdbError implements Exception {
  /// Creates the error.
  const new(this.message, {this.status});

  /// What failed (method, path, status).
  final String message;

  /// HTTP status, or null when the request never got an answer.
  final int? status;

  @override
  String toString() => 'RtdbError($status): $message';
}

/// The REST client.
class RtdbClient {
  /// Creates a client for [databaseUrl] authenticated by [idToken].
  new({
    required String databaseUrl,
    required this.idToken,
    http.Client? httpClient,
  }) : _base = databaseUrl.endsWith('/')
           ? databaseUrl.substring(0, databaseUrl.length - 1)
           : databaseUrl,
       _http = httpClient ?? http.Client();

  final String _base;

  /// Token source.
  final IdTokenSource idToken;
  final http.Client _http;

  Future<Uri> _uri(String path) async {
    final segments = path.split('/').where((s) => s.isNotEmpty);
    final encoded = segments.map(Uri.encodeComponent).join('/');
    return Uri.parse('$_base/$encoded.json')
        .replace(queryParameters: {'auth': await idToken()});
  }

  /// Reads [path]; null when absent.
  Future<Object?> get(String path) async => _decode(await _send('GET', path));

  /// Writes [value] at [path]; returns it as stored (server times resolved).
  Future<Object?> put(String path, Object? value) async =>
      _decode(await _send('PUT', path, body: value));

  /// Removes [path].
  Future<void> delete(String path) async {
    await _send('DELETE', path);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    final request = http.Request(method, await _uri(path));
    if (method == 'PUT') request.body = jsonEncode(body);
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(request));
    } on http.ClientException {
      throw RtdbError('network error: $method $path');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw RtdbError(
        '$method $path: HTTP ${res.statusCode}',
        status: res.statusCode,
      );
    }
    return res;
  }

  static Object? _decode(http.Response res) =>
      res.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
}
