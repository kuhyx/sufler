// End to end: the importer talking to the real wrapper route, which talks to
// a fake Google. Pins the /api/gdoc contract in DOCS-contract.md from both
// sides at once, so the wrapper and the importer cannot drift apart again.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sufler/import/google_doc.dart';

import 'harness.dart';

/// What the fake Google answers for each document id.
Future<void> _google(HttpRequest r) async {
  final id = r.uri.pathSegments[2];
  switch (id) {
    case 'login':
      // A private doc redirects to a sign-in page: 200 HTML.
      r.response.headers.contentType = ContentType.html;
      r.response.write('<html>Sign in</html>');
    case 'unauthorized':
      r.response.statusCode = 401;
    case 'forbidden':
      r.response.statusCode = 403;
    case 'missing':
      r.response.statusCode = 404;
    case 'broken':
      r.response.statusCode = 500;
  }
}

void main() {
  late Harness h;
  late FakeUpstream up;
  setUp(() async {
    up = await FakeUpstream.start(_google);
    h = await Harness.start(google: up.base);
  });
  tearDown(() async {
    await h.stop();
    await up.stop();
  });

  /// The web build's view: every download goes to the wrapper's /api/gdoc.
  http.Client viaWrapper() => MockClient((req) async {
    final id = googleDocId(req.url.toString());
    final r = await h.get('/api/gdoc?id=$id');
    return http.Response.bytes(
      await bytesOf(r),
      r.statusCode,
      headers: {'content-type': r.headers.contentType.toString()},
    );
  });

  Future<Object?> importing(String id) => importGoogleDoc(
    'https://docs.google.com/document/d/$id/edit',
    client: viaWrapper(),
  );

  for (final id in ['login', 'unauthorized', 'forbidden', 'missing']) {
    test(
      '$id upstream: wrapper says 403 not_shared, importer agrees',
      () async {
        final r = await h.get('/api/gdoc?id=$id');
        expect(r.statusCode, 403);
        expect(await jsonOf(r), {'error': 'not_shared'});
        await expectLater(
          importing(id),
          throwsA(
            isA<GoogleDocException>().having(
              (e) => e.message,
              'message',
              contains('anyone with the link'),
            ),
          ),
        );
      },
    );
  }

  test('any other upstream failure is a 502 the importer reports', () async {
    final r = await h.get('/api/gdoc?id=broken');
    expect(r.statusCode, 502);
    expect(await jsonOf(r), {'error': 'Google Docs answered 500'});
    await expectLater(
      importing('broken'),
      throwsA(
        isA<GoogleDocException>().having(
          (e) => e.message,
          'message',
          allOf(contains('HTTP 502'), contains('Google Docs answered 500')),
        ),
      ),
    );
  });
}
