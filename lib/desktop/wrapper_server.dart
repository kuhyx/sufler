import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sufler/anki/anki_deck.dart';
import 'package:sufler/anki/apkg_writer.dart';
import 'package:sufler/desktop/static_content_type.dart';
import 'package:sufler/desktop/upstream_routes.dart';
import 'package:sufler/model/json.dart';

/// Local HTTP server backing the desktop app (a Flutter **web** build in a
/// Chrome `--app` window, see the `flutter-desktop-to-chrome` skill).
///
/// Serves the build and does what a browser page cannot:
/// * `GET /api/gdoc?id=` fetches a Google Doc as docx (Google sends no CORS
///   headers, so the page cannot fetch it itself);
/// * `POST /api/apkg` writes an Anki deck with sqlite3 (no sqlite on web);
/// * `/api/tts/*` reverse-proxies the local voice service.
///
/// Must import nothing from Flutter: it is compiled with `dart build cli`
/// for the plain Dart VM (guarded by test/desktop/import_graph_test.dart).
///
/// Binds to IPv4 loopback only: the routes are unauthenticated and the
/// proxies would otherwise be an open relay on the network.
class WrapperServer {
  /// Creates a server for [webRoot]; upstream bases are injectable for tests.
  WrapperServer({required this.webRoot, Uri? googleBase, Uri? ttsBase})
    : upstream = UpstreamRoutes(
        googleBase: googleBase ?? Uri.parse('https://docs.google.com'),
        ttsBase: ttsBase ?? Uri.parse('http://127.0.0.1:8791'),
      );

  /// Directory holding the built Flutter web assets.
  final String webRoot;

  /// The proxy routes (Google Docs, voice service).
  final UpstreamRoutes upstream;

  HttpServer? _server;

  /// Port the server listens on, once [start] has completed.
  int get port => _server!.port;

  /// Address the server listens on, once [start] has completed.
  InternetAddress get address => _server!.address;

  /// Binds loopback on [requestedPort] (0 = any; tests) and starts serving.
  /// Production passes the fixed `kWrapperPort`, see why there.
  Future<void> start(int requestedPort) async {
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      requestedPort,
    );
    // Requests run side by side: a render poll must not wait for a pack
    // download, and every route is independent.
    _server!.listen((request) => unawaited(_respond(request)));
  }

  /// Stops serving and releases the port.
  Future<void> stop() async {
    upstream.close();
    await _server?.close(force: true);
  }

  Future<void> _respond(HttpRequest request) async {
    try {
      if (_isCrossSiteWrite(request)) {
        await request.drain<void>();
        request.response.statusCode = HttpStatus.forbidden;
      } else {
        await _handle(request);
      }
    } on Exception catch (e) {
      sendJsonError(request.response, HttpStatus.internalServerError, '$e');
    }
    await request.response.close();
  }

  /// A write sent by some other site's page: any website open in the browser
  /// can POST here without a preflight. The app's page sends its own origin;
  /// local tools (curl, tests) send none.
  bool _isCrossSiteWrite(HttpRequest request) {
    if (request.method == 'GET' || request.method == 'HEAD') return false;
    final origin = request.headers.value('origin');
    return origin != null && origin != 'http://127.0.0.1:$port';
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (path == '/api/health') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'app': 'sufler'}));
    } else if (path == '/api/gdoc') {
      await upstream.gdoc(request);
    } else if (path == '/api/apkg') {
      await _apkg(request);
    } else if (path.startsWith(UpstreamRoutes.ttsPrefix)) {
      await upstream.tts(request);
    } else {
      await _static(request, path);
    }
  }

  Future<void> _apkg(HttpRequest request) async {
    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      return;
    }
    final AnkiDeck deck;
    try {
      deck = deckFromJson(jsonDecode(await utf8.decodeStream(request)) as Json);
    } on Object catch (e) {
      // FormatException for bad JSON, TypeError for a wrong shape.
      return sendJsonError(request.response, HttpStatus.badRequest, '$e');
    }
    request.response.headers
      ..contentType = ContentType.binary
      ..set('content-disposition', 'attachment; filename="sufler.apkg"');
    request.response.add(writeApkg(deck));
  }

  Future<void> _static(HttpRequest request, String path) async {
    final relative = path == '/' ? 'index.html' : path.substring(1);
    final resolved = p.normalize(p.join(webRoot, relative));
    // coverage:ignore-start
    // Defence in depth: HttpServer already collapses `..` before a handler
    // runs, so this is unreachable today.
    if (!p.isWithin(webRoot, resolved)) {
      request.response.statusCode = HttpStatus.forbidden;
      return;
    }
    // coverage:ignore-end
    final file = File(resolved);
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    request.response.headers.contentType = staticContentTypeFor(resolved);
    await request.response.addStream(file.openRead());
  }
}
