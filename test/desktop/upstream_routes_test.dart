import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  late Harness h;
  late FakeUpstream up;
  tearDown(() async {
    await h.stop();
    await up.stop();
  });

  group('gdoc', () {
    setUp(() async {
      up = await FakeUpstream.start((r) async {
        if (r.uri.path.contains('private')) {
          r.response.headers.contentType = ContentType.html;
          r.response.write('<html>Sign in</html>');
        } else if (r.uri.path.contains('gone')) {
          r.response.statusCode = 404;
        } else {
          r.response.add([80, 75, 3, 4]);
        }
      });
      h = await Harness.start(google: up.base);
    });

    test('proxies the docx export of a document id', () async {
      final r = await h.get('/api/gdoc?id=abc_DEF-123');
      expect(r.statusCode, 200);
      expect(await bytesOf(r), [80, 75, 3, 4]);
      expect(r.headers.value('access-control-allow-origin'), isNull);
      expect(up.seen, ['GET /document/d/abc_DEF-123/export?format=docx']);
    });

    test('rejects an id that could escape the path', () async {
      final r = await h.get('/api/gdoc?id=../../x');
      expect(r.statusCode, 400);
      expect(await jsonOf(r), contains('error'));
      expect(up.seen, isEmpty);
    });

    test('a login page means the doc is not shared', () async {
      final r = await h.get('/api/gdoc?id=private1');
      expect(r.statusCode, 403);
      expect(await jsonOf(r), contains('error'));
    });

    test('an upstream error is a 502', () async {
      final r = await h.get('/api/gdoc?id=gone1');
      expect(r.statusCode, 502);
      await r.drain<void>();
    });
  });

  group('tts proxy', () {
    setUp(() async {
      up = await FakeUpstream.start((r) async {
        if (r.uri.path == '/render') {
          final body = await utf8.decodeStream(r);
          r.response.headers.contentType = ContentType.json;
          r.response.write(jsonEncode({'jobId': 'j1', 'echo': body.length}));
        } else if (r.uri.path == '/packs/s1.zip') {
          r.response.add([1, 2, 3]);
        } else {
          r.response.headers.contentType = ContentType.json;
          r.response.write('{"ok":true}');
        }
      });
      h = await Harness.start(tts: up.base);
    });

    test('forwards GET with path and query', () async {
      final r = await h.get('/api/tts/jobs/j1?x=1');
      expect(r.statusCode, 200);
      expect(r.headers.contentType?.mimeType, 'application/json');
      expect(await jsonOf(r), {'ok': true});
      expect(up.seen, ['GET /jobs/j1?x=1']);
    });

    test('forwards POST bodies and binary answers', () async {
      final r = await h.post('/api/tts/render', '{"id":"s1"}');
      expect(await jsonOf(r), {'jobId': 'j1', 'echo': 11});
      expect(await bytesOf(await h.get('/api/tts/packs/s1.zip')), [1, 2, 3]);
    });
  });

  test('tts down is a 503 with a JSON error', () async {
    up = await FakeUpstream.start((_) async {});
    final dead = up.base;
    await up.stop();
    h = await Harness.start(tts: dead);
    final r = await h.get('/api/tts/health');
    expect(r.statusCode, 503);
    final body = await jsonOf(r)! as Map<String, Object?>;
    expect(body['error'], contains('voice service'));
  });
}
