import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/anki/sufler_cards.dart';

import '../anki/fixture.dart';
import 'harness.dart';

void main() {
  late Harness h;
  tearDown(() => h.stop());

  group('static', () {
    setUp(() async => h = await Harness.start());

    test('serves index with html and wasm as application/wasm', () async {
      final index = await h.get('/');
      expect(index.statusCode, 200);
      expect(index.headers.contentType?.mimeType, 'text/html');
      await index.drain<void>();
      final wasm = await h.get('/main.dart.wasm');
      expect(wasm.headers.contentType?.mimeType, 'application/wasm');
      expect(await bytesOf(wasm), [0, 97, 115, 109]);
      final js = await h.get('/main.dart.js');
      expect(js.headers.contentType?.mimeType, 'text/javascript');
      await js.drain<void>();
    });

    test('missing file is 404, health names the app', () async {
      final missing = await h.get('/nope.js');
      expect(missing.statusCode, 404);
      await missing.drain<void>();
      expect(await jsonOf(await h.get('/api/health')), {'app': 'sufler'});
    });

    test('binds loopback only', () {
      expect(h.server.address, InternetAddress.loopbackIPv4);
    });
  });

  group('apkg', () {
    setUp(() async => h = await Harness.start());

    test('builds an apkg from a posted deck', () async {
      final script = fixtureScript();
      final deck = buildDeck(
        script,
        annaAndSong,
        audio: fixturePack(script.id, [2]),
      );
      final r = await h.post('/api/apkg', jsonEncode(deck.toJson()));
      expect(r.statusCode, 200);
      final zip = ZipDecoder().decodeBytes(await bytesOf(r));
      expect(zip.findFile('collection.anki2'), isNotNull);
      expect(jsonDecode(utf8.decode(zip.findFile('media')!.content)), {
        '0': 'sufler-abc123-2.ogg',
      });
    });

    test('rejects a cross-site write and a malformed body', () async {
      final cross = await h.post(
        '/api/apkg',
        '{}',
        origin: 'https://evil.example',
      );
      expect(cross.statusCode, 403);
      await cross.drain<void>();
      final own = await h.post(
        '/api/apkg',
        'not json',
        origin: 'http://127.0.0.1:${h.server.port}',
      );
      expect(own.statusCode, 400);
      expect(await jsonOf(own), contains('error'));
    });

    test('GET is not allowed', () async {
      final r = await h.get('/api/apkg');
      expect(r.statusCode, 405);
      await r.drain<void>();
    });
  });
}
