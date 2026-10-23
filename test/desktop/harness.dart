import 'dart:convert';
import 'dart:io';

import 'package:sufler/desktop/wrapper_server.dart';

/// A running wrapper on an ephemeral port plus a scratch web root.
class Harness {
  Harness._(this.server, this.webRoot, this.client);

  /// Starts a wrapper whose upstreams are [google] and [tts].
  static Future<Harness> start({Uri? google, Uri? tts}) async {
    final webRoot = Directory.systemTemp.createTempSync('sufler_web');
    File('${webRoot.path}/index.html').writeAsStringSync('<html></html>');
    File('${webRoot.path}/main.dart.wasm').writeAsBytesSync([0, 97, 115, 109]);
    File('${webRoot.path}/main.dart.js').writeAsStringSync('main();');
    final server = WrapperServer(
      webRoot: webRoot.path,
      googleBase: google,
      ttsBase: tts,
    );
    await server.start(0);
    return Harness._(server, webRoot, HttpClient());
  }

  final WrapperServer server;
  final Directory webRoot;
  final HttpClient client;

  Uri uri(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  Future<HttpClientResponse> get(String path) async =>
      (await client.getUrl(uri(path))).close();

  Future<HttpClientResponse> post(
    String path,
    String body, {
    String? origin,
  }) async {
    final request = await client.postUrl(uri(path));
    request.headers.contentType = ContentType.json;
    if (origin != null) request.headers.set('origin', origin);
    request.write(body);
    return request.close();
  }

  Future<void> stop() async {
    client.close(force: true);
    await server.stop();
    webRoot.deleteSync(recursive: true);
  }
}

/// Reads a whole response body.
Future<List<int>> bytesOf(HttpClientResponse r) async => [
  for (final chunk in await r.toList()) ...chunk,
];

/// Reads a whole response body as JSON.
Future<Object?> jsonOf(HttpClientResponse r) async =>
    jsonDecode(utf8.decode(await bytesOf(r)));

/// A fake upstream: records requests and answers with [handler].
class FakeUpstream {
  FakeUpstream._(this._server);

  static Future<FakeUpstream> start(
    Future<void> Function(HttpRequest request) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeUpstream._(server);
    server.listen((request) async {
      fake.seen.add('${request.method} ${request.uri}');
      await handler(request);
      await request.response.close();
    });
    return fake;
  }

  final HttpServer _server;
  final List<String> seen = [];

  Uri get base => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> stop() => _server.close(force: true);
}
