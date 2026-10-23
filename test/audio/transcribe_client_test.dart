import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sufler/audio/transcribe_client.dart';

TranscribeClient _client(Future<http.Response> Function(http.Request) h) =>
    TranscribeClient(
      client: MockClient(h),
      base: Uri.parse('http://127.0.0.1:8792/'),
    );

void main() {
  test('posts the WAV and reads text and speech bounds', () async {
    late http.Request sent;
    final c = _client((r) async {
      sent = r;
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'text': ' Dzień dobry ',
            'segments': <Object>[],
            'speechStart': 0.4,
            'speechEnd': 2,
            'engine': 'faster-whisper@1/x',
          }),
        ),
        200,
      );
    });
    final t = await c.transcribe(Uint8List.fromList([1, 2]));
    expect(sent.method, 'POST');
    expect(
      sent.url.toString(),
      'http://127.0.0.1:8792/api/tts/transcribe?lang=pl',
    );
    expect(sent.headers['content-type'], 'audio/wav');
    expect(sent.bodyBytes, [1, 2]);
    expect(t!.text, 'Dzień dobry');
    expect(t.speechStart, 0.4);
    expect(t.speechEnd, 2.0);
  });

  test('no speech: null bounds', () async {
    final c = _client(
      (_) async => http.Response(
        jsonEncode({'text': '', 'speechStart': null, 'speechEnd': null}),
        200,
      ),
    );
    final t = await c.transcribe(Uint8List(0));
    expect(t!.speechStart, isNull);
  });

  test('reads word times; an older service without words gives none', () async {
    final c = _client(
      (_) async => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'text': 'Raz dwa',
            'speechStart': 0.5,
            'speechEnd': 1.9,
            'words': [
              {'start': 0.5, 'end': 0.9, 'word': ' Raz'},
              {'start': 1, 'end': 1.9, 'word': ' dwa.'},
            ],
          }),
        ),
        200,
      ),
    );
    final t = (await c.transcribe(Uint8List(0)))!;
    expect(t.words, [
      (text: ' Raz', start: 0.5, end: 0.9),
      (text: ' dwa.', start: 1.0, end: 1.9),
    ]);
    final old = _client(
      (_) async => http.Response(jsonEncode({'text': 'x'}), 200),
    );
    expect((await old.transcribe(Uint8List(0)))!.words, isEmpty);
  });

  test('404, 503, garbage and network errors mean no transcript', () async {
    for (final status in [404, 503, 500]) {
      final c = _client((_) async => http.Response('{}', status));
      expect(await c.transcribe(Uint8List(0)), isNull, reason: '$status');
    }
    expect(
      await _client((_) async => http.Response('nie json', 200))
          .transcribe(Uint8List(0)),
      isNull,
    );
    expect(
      await _client((_) => throw http.ClientException('down'))
          .transcribe(Uint8List(0)),
      isNull,
    );
  });
}
