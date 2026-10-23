import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart' show InMemoryCredentialStore;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sufler/assist/firebase_config.dart';
import 'package:sufler/assist/firebase_session.dart';

const _config = FirebaseConfig(
  apiKey: 'key',
  databaseUrl: 'https://db.example',
  syncUid: 'the-uid',
  serverClientId: 'web-client',
);

FirebaseSession _session({
  FirebaseConfig config = _config,
  String? googleToken = 'google-id-token',
  String uid = 'the-uid',
  List<String>? asked,
}) => FirebaseSession(
  config: config,
  store: InMemoryCredentialStore(),
  googleToken: (clientId) async {
    asked?.add(clientId);
    return googleToken;
  },
  httpClient: MockClient((r) async {
    expect(r.url.path, endsWith('accounts:signInWithIdp'));
    return http.Response(
      jsonEncode({
        'localId': uid,
        'idToken': 'firebase-id',
        'refreshToken': 'refresh',
        'expiresIn': '3600',
      }),
      200,
    );
  }),
);

void main() {
  test('signs in with the Web client id and keeps the session', () async {
    final asked = <String>[];
    final s = _session(asked: asked);
    expect(await s.signedIn(), isFalse);
    expect(await s.signIn(), isTrue);
    expect(asked, ['web-client']);
    expect(await s.signedIn(), isTrue);
    expect(await s.idToken(), 'firebase-id');
  });

  test('the wrong Google account is refused and nothing is stored', () async {
    final s = _session(uid: 'someone-else');
    expect(await s.signIn(), isFalse);
    expect(await s.signedIn(), isFalse);
  });

  test('a cancelled picker is not signed in', () async {
    final s = _session(googleToken: null);
    expect(await s.signIn(), isFalse);
    expect(await s.signedIn(), isFalse);
  });

  test('a placeholder build (CI) never opens the picker', () async {
    final asked = <String>[];
    final s = _session(
      config: const FirebaseConfig(
        apiKey: '',
        databaseUrl: '',
        syncUid: '',
        serverClientId: '',
      ),
      asked: asked,
    );
    expect(await s.signIn(), isFalse);
    expect(await s.signedIn(), isFalse);
    expect(asked, isEmpty);
  });
}
