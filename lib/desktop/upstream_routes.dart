/// The wrapper's two proxies: Google Docs export and the local voice service.
library;

import 'dart:convert';
import 'dart:io';

/// Writes `{"error": message}` with [status].
void sendJsonError(HttpResponse response, int status, String message) {
  response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode({'error': message}));
}

/// MIME type of a `.docx`.
final ContentType docxType = ContentType(
  'application',
  'vnd.openxmlformats-officedocument.wordprocessingml.document',
);

/// Google Docs ids are base64url-ish; anything else is refused before it can
/// reshape the upstream path.
final RegExp _docId = RegExp(r'^[A-Za-z0-9_-]{1,200}$');

/// Proxies to [googleBase] and [ttsBase] with one shared [HttpClient].
class UpstreamRoutes {
  /// Creates the routes.
  new({required this.googleBase, required this.ttsBase});

  /// Path prefix proxied to the voice service (`/api/tts/x` -> `/x`).
  static const ttsPrefix = '/api/tts/';

  /// `https://docs.google.com` in production.
  final Uri googleBase;

  /// The voice service, `http://127.0.0.1:8791` in production.
  final Uri ttsBase;

  final HttpClient _client = HttpClient();

  /// Releases the client.
  void close() => _client.close(force: true);

  /// `GET /api/gdoc?id=<id>`: the document's docx export.
  Future<void> gdoc(HttpRequest request) async {
    final id = request.uri.queryParameters['id'] ?? '';
    if (!_docId.hasMatch(id)) {
      return sendJsonError(request.response, 400, 'invalid document id');
    }
    final url = googleBase.replace(
      path: '/document/d/$id/export',
      queryParameters: {'format': 'docx'},
    );
    final HttpClientResponse upstream;
    try {
      upstream = await (await _client.getUrl(url)).close();
    } on IOException catch (e) {
      return sendJsonError(request.response, 502, 'Google Docs: $e');
    }
    if (upstream.statusCode != 200) {
      await upstream.drain<void>();
      return sendJsonError(
        request.response,
        502,
        'Google Docs answered ${upstream.statusCode}',
      );
    }
    // A private doc redirects to a sign-in page, which arrives as 200 HTML.
    if (upstream.headers.contentType?.mimeType == 'text/html') {
      await upstream.drain<void>();
      return sendJsonError(
        request.response,
        403,
        'document is not shared as "anyone with the link"',
      );
    }
    request.response.headers.contentType = docxType;
    await request.response.addStream(upstream);
  }

  /// `/api/tts/<rest>`: forwarded verbatim (method, query, body, content
  /// type) to `<ttsBase>/<rest>`; 503 with a JSON error when it is down.
  Future<void> tts(HttpRequest request) async {
    final rest = request.uri.path.substring(ttsPrefix.length);
    final url = ttsBase.replace(
      path: '/$rest',
      query: request.uri.hasQuery ? request.uri.query : null,
    );
    final HttpClientResponse upstream;
    try {
      final out = await _client.openUrl(request.method, url);
      final type = request.headers.contentType;
      if (type != null) out.headers.contentType = type;
      await out.addStream(request);
      upstream = await out.close();
    } on IOException catch (e) {
      return sendJsonError(
        request.response,
        HttpStatus.serviceUnavailable,
        'voice service at $ttsBase is not running ($e)',
      );
    }
    request.response.statusCode = upstream.statusCode;
    final type = upstream.headers.contentType;
    if (type != null) request.response.headers.contentType = type;
    await request.response.addStream(upstream);
  }
}
