import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/assist/assist_error.dart';
import 'package:sufler/assist/assist_payload.dart';
import 'package:sufler/assist/pc_session.dart';
import 'package:sufler/assist/relay_assistant.dart';
import 'package:sufler/assist/rtdb_client.dart';

import '../rehearsal/fixture.dart';
import 'fake_rtdb.dart';

class FakeSession implements PcSession {
  bool session = true;
  bool signInWorks = false;
  int signIns = 0;

  @override
  Future<bool> signedIn() async => session;

  @override
  Future<bool> signIn() async {
    signIns++;
    session = signInWorks;
    return session;
  }
}

const dev = 'dev-1';

void main() {
  late FakeRtdb db;
  late FakeSession session;
  late RelayAssistant relay;

  setUp(() {
    db = FakeRtdb();
    session = FakeSession();
    relay = RelayAssistant(
      rtdb: RtdbClient(
        databaseUrl: 'https://db.example/',
        idToken: () async => 'tok',
        httpClient: db.client,
      ),
      deviceId: () async => dev,
      session: session,
      pollEvery: const Duration(milliseconds: 5),
      explainTimeout: const Duration(milliseconds: 300),
      renderTimeout: const Duration(milliseconds: 300),
    );
  });

  /// Plays the PC: answers every request with [answer] after a few polls.
  void pcAnswers(Map<String, Object?> Function(Map<String, Object?>) answer) {
    db.onPut = (path, value) {
      final rid = RegExp(r'^sufler/requests/(.+)$').firstMatch(path)?[1];
      if (rid == null) return;
      Timer(const Duration(milliseconds: 20), () {
        db
          ..write('sufler/results/$rid', {
            ...answer(value! as Map<String, Object?>),
            'at': db.serverMs,
          })
          ..write(path, null);
      });
    };
  }

  test(
    'explain writes one request and reads (then deletes) its result',
    () async {
      late Map<String, Object?> request;
      pcAnswers((req) {
        request = req;
        return {'ok': true, 'text': 'Znaczy: dzień dobry.'};
      });
      final script = fixtureScript();
      final text = await relay.explain(
        script: script,
        index: 1,
        selection: 'x',
      );
      expect(text, 'Znaczy: dzień dobry.');
      expect(request['kind'], 'explain');
      expect(request['deviceId'], dev);
      expect(request['ts'], db.serverMs); // server time, not the phone's
      final payload = jsonDecode(request['payload']! as String);
      expect(payload, explainPayload(script, 1, 'x'));
      expect(db.read('sufler/results'), isNull);
      expect(db.tokens, {'tok'});
    },
  );

  test('an error result throws its reason', () async {
    pcAnswers((_) => {'ok': false, 'error': 'claude timed out after 90 s'});
    await expectLater(
      relay.explain(script: fixtureScript(), index: 1, selection: 'x'),
      throwsA(
        isA<AssistantError>().having((e) => e.message, 'm', contains('90 s')),
      ),
    );
  });

  test('no answer by the deadline: throws and withdraws the request', () async {
    await expectLater(
      relay.explain(script: fixtureScript(), index: 1, selection: 'x'),
      throwsA(isA<AssistantError>()),
    );
    expect(db.read('sufler/requests'), isNull);
  });

  test(
    'a dead session or no network is an AssistantError, never raw',
    () async {
      final broken = RelayAssistant(
        rtdb: RtdbClient(
          databaseUrl: 'https://db.example/',
          idToken: () async => throw StateError('refresh token revoked'),
          httpClient: db.client,
        ),
        deviceId: () async => dev,
        session: session,
      );
      await expectLater(
        broken.explain(script: fixtureScript(), index: 1, selection: 'x'),
        throwsA(isA<AssistantError>()),
      );
      expect(
        await broken.renderLine(script: fixtureScript(), index: 2),
        isNull,
      );
    },
  );

  test('renderLine decodes audioB64; failures are null', () async {
    pcAnswers((req) {
      final body = jsonDecode(req['payload']! as String) as Map;
      expect(req['kind'], 'render_line');
      expect(body['index'], 2);
      return {
        'ok': true,
        'audioB64': base64Encode([0x4f, 0x67, 0x67, 0x53]),
      };
    });
    final clip = await relay.renderLine(script: fixtureScript(), index: 2);
    expect(clip, [0x4f, 0x67, 0x67, 0x53]);
    pcAnswers((_) => {'ok': false, 'error': 'line 3 has nothing to say'});
    expect(await relay.renderLine(script: fixtureScript(), index: 3), isNull);
  });

  test('signed out: asks to sign in once, then gives up cleanly', () async {
    session.session = false;
    await expectLater(
      relay.explain(script: fixtureScript(), index: 1, selection: 'x'),
      throwsA(isA<AssistantError>()),
    );
    expect(await relay.renderLine(script: fixtureScript(), index: 2), isNull);
    expect(session.signIns, 2);
    expect(db.log, isEmpty);
    session.signInWorks = true;
    pcAnswers((_) => {'ok': true, 'text': 'ok'});
    expect(
      await relay.explain(script: fixtureScript(), index: 1, selection: 'x'),
      'ok',
    );
  });

  test(
    'pcOnline compares the beat with server time, never the phone',
    () async {
      final seen = <bool>[];
      db.write('sufler/presence/pc', {'beat': db.serverMs - 10000});
      final sub = relay.pcOnline.listen(seen.add);
      await pumpEventQueue();
      expect(seen, [true]);
      db.serverMs += 80000; // the PC stopped beating 90 s ago
      await relay.checkPresenceNow();
      db.write('sufler/presence', null);
      await relay.checkPresenceNow();
      expect(seen, [true, false]); // distinct values only
      expect(db.read('sufler/clients/$dev/seen'), db.serverMs);
      await sub.cancel();
    },
  );

  test('pcOnline is false while signed out, without any request', () async {
    session.session = false;
    expect(await relay.pcOnline.first, isFalse);
    expect(db.log, isEmpty);
    expect(session.signIns, 0); // never pops the account picker by itself
  });

  test('request ids are what the PC worker accepts', () {
    final ids = {for (var i = 0; i < 50; i++) newRequestId()};
    expect(ids, hasLength(50));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[A-Za-z0-9_-]{16,64}$')));
    }
  });
}
