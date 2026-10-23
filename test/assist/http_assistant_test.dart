import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sufler/assist/assist_error.dart';
import 'package:sufler/assist/assist_payload.dart';
import 'package:sufler/assist/http_assistant.dart';

import '../rehearsal/fixture.dart';

HttpAssistant _assistant(Future<http.Response> Function(http.Request) h) =>
    HttpAssistant(
      client: MockClient(h),
      base: Uri.parse('http://127.0.0.1:8792/'),
    );

http.Response _json(Object body, int status) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

void main() {
  final script = fixtureScript();

  test(
    'explain posts the context to the wrapper and returns the text',
    () async {
      late http.Request sent;
      final a = _assistant((r) async {
        sent = r;
        return _json({'text': 'Znaczy: dzień dobry.'}, 200);
      });
      final text = await a.explain(
        script: script,
        index: 1,
        selection: 'Wilku',
      );
      expect(text, 'Znaczy: dzień dobry.');
      expect(sent.method, 'POST');
      expect(sent.url.toString(), 'http://127.0.0.1:8792/api/tts/explain');
      expect(sent.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(sent.body), explainPayload(script, 1, 'Wilku'));
    },
  );

  test('explain failures throw with the service reason', () async {
    final busy = _assistant(
      (_) async => _json({'error': 'claude timed out after 90 s'}, 503),
    );
    await expectLater(
      busy.explain(script: script, index: 1, selection: 'x'),
      throwsA(
        isA<AssistantError>().having(
          (e) => e.message,
          'message',
          contains('claude timed out'),
        ),
      ),
    );
    final down = _assistant((_) async => throw http.ClientException('refused'));
    await expectLater(
      down.explain(script: script, index: 1, selection: 'x'),
      throwsA(isA<AssistantError>()),
    );
  });

  test('renderLine posts {script, index} and returns the ogg bytes', () async {
    late http.Request sent;
    final a = _assistant((r) async {
      sent = r;
      return http.Response.bytes([0x4f, 0x67, 0x67, 0x53], 200);
    });
    final clip = await a.renderLine(script: script, index: 2);
    expect(clip, [0x4f, 0x67, 0x67, 0x53]);
    expect(sent.url.path, '/api/tts/render_line');
    expect(jsonDecode(sent.body), renderLinePayload(script, 2));
  });

  test('renderLine is null on any failure', () async {
    final bad = _assistant((_) async => _json({'error': 'no line'}, 400));
    expect(await bad.renderLine(script: script, index: 3), isNull);
    final down = _assistant((_) async => throw http.ClientException('x'));
    expect(await down.renderLine(script: script, index: 2), isNull);
  });

  test(
    'pcOnline polls /api/tts/health, every answer, replayed to late listeners',
    () {
      fakeAsync((clock) {
        var up = true;
        final paths = <String>[];
        final a = _assistant((r) async {
          paths.add(r.url.path);
          if (!up) throw http.ClientException('down');
          return _json({'ok': true}, 200);
        });
        final seen = <bool>[];
        final sub = a.pcOnline.listen(seen.add);
        clock.flushMicrotasks();
        expect(seen, [true]);
        clock.elapse(const Duration(seconds: 30));
        expect(seen, [true, true]); // repeats too: PcLink.back waits for one
        final late = <bool>[];
        final lateSub = a.pcOnline.listen(late.add);
        clock.flushMicrotasks();
        expect(late, [true]); // the current state at once
        lateSub.cancel();
        up = false;
        clock.elapse(const Duration(seconds: 30));
        expect(seen, [true, true, false]);
        expect(paths.toSet(), {'/api/tts/health'});
        sub.cancel();
        final calls = paths.length;
        clock.elapse(const Duration(minutes: 5));
        expect(paths.length, calls); // no polling without a listener
      });
    },
  );
}
