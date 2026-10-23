import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sufler/tts/render_client.dart';
import 'package:sufler/tts/render_pack.dart';

import '../anki/fixture.dart';

final _base = Uri.parse('http://127.0.0.1:8792/');

RenderClient _client(MockClientHandler handler) => RenderClient(
  client: MockClient(handler),
  base: _base,
  pollInterval: Duration.zero,
);

void main() {
  test('available when health answers 200', () async {
    final seen = <String>[];
    final ok = await _client((r) async {
      seen.add('${r.method} ${r.url.path}');
      return http.Response('{"ok":true}', 200);
    }).available();
    expect(ok, isTrue);
    expect(seen, ['GET /api/tts/health']);
  });

  test('unavailable on 503 or a network error', () async {
    expect(
      await _client((_) async => http.Response('{}', 503)).available(),
      isFalse,
    );
    expect(
      await _client(
        (_) async => throw http.ClientException('down'),
      ).available(),
      isFalse,
    );
  });

  test('render: post, poll with progress, download the pack', () async {
    final script = fixtureScript();
    final polls = [
      {'done': 0, 'total': 3, 'state': 'running'},
      {'done': 2, 'total': 3, 'state': 'running'},
      {'done': 3, 'total': 3, 'state': 'done'},
    ];
    final seen = <String>[];
    Object? posted;
    final client = _client((r) async {
      seen.add('${r.method} ${r.url.path}');
      if (r.url.path == '/api/tts/render') {
        posted = jsonDecode(r.body);
        return http.Response('{"jobId":"j1"}', 200);
      }
      if (r.url.path == '/api/tts/jobs/j1') {
        return http.Response(jsonEncode(polls.removeAt(0)), 200);
      }
      return http.Response.bytes(packZip(script.id, [2, 4]), 200);
    });
    final events = await client.render(script).toList();
    expect((posted! as Map)['id'], script.id);
    expect(events.map((e) => e.done), [0, 2, 3, 3]);
    expect(events.last.total, 3);
    expect(events.take(3).every((e) => e.pack == null), isTrue);
    expect(events.last.pack!.clip(2), isNotNull);
    expect(seen.last, 'GET /api/tts/packs/abc123.zip');
  });

  test('a failed job or a bad answer is a stream error', () async {
    final failed = _client((r) async {
      if (r.url.path.endsWith('/render')) {
        return http.Response('{"jobId":"j"}', 200);
      }
      return http.Response('{"done":1,"total":3,"state":"error"}', 200);
    });
    await expectLater(
      failed.render(fixtureScript()),
      emitsInOrder([isA<RenderProgress>(), emitsError(isA<RenderException>())]),
    );
    final down = _client((_) async => http.Response('{"error":"x"}', 503));
    await expectLater(
      down.render(fixtureScript()),
      emitsError(isA<RenderException>()),
    );
  });

  test('on io (Android) rendering is unavailable', () async {
    expect(await renderAvailable(), isFalse);
    await expectLater(
      renderPack(fixtureScript()),
      emitsError(isA<UnsupportedError>()),
    );
  });
}
