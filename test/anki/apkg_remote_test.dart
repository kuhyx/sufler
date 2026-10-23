import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sufler/anki/apkg_remote.dart';
import 'package:sufler/anki/sufler_cards.dart';

import 'fixture.dart';

void main() {
  final deck = buildDeck(fixtureScript(), annaAndSong);
  final base = Uri.parse('http://127.0.0.1:8792/');

  test('posts the deck JSON to the wrapper and returns the bytes', () async {
    late http.Request seen;
    final bytes = await postDeck(
      deck,
      base: base,
      client: MockClient((r) async {
        seen = r;
        return http.Response.bytes([1, 2, 3], 200);
      }),
    );
    expect(bytes, [1, 2, 3]);
    expect(seen.url.toString(), 'http://127.0.0.1:8792/api/apkg');
    expect(seen.headers['content-type'], startsWith('application/json'));
    expect((jsonDecode(seen.body) as Map)['title'], 'Sztuka');
  });

  test('a non-200 answer is an ApkgExportException', () async {
    await expectLater(
      postDeck(
        deck,
        base: base,
        client: MockClient((_) async => http.Response('nope', 404)),
      ),
      throwsA(
        isA<ApkgExportException>().having(
          (e) => e.toString(),
          'message',
          contains('404'),
        ),
      ),
    );
  });
}
