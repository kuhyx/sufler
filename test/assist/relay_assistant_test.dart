import 'dart:async';
import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart' show E2eCipher;
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/assist/assist_error.dart';
import 'package:sufler/assist/assist_payload.dart';
import 'package:sufler/assist/pc_session.dart';
import 'package:sufler/assist/relay_assistant.dart';
import 'package:sufler/assist/relay_seal.dart';
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

/// The shared key in tests (the PC side seals with the same one).
final sealer = RelaySealer(E2eCipher(List.filled(32, 7)));

void main() {
  late FakeRtdb db;
  late FakeSession session;
  late RelayAssistant relay;
  RelaySealer? key;
  final written = <Object?>[]; // results as the PC stored them

  setUp(() {
    key = sealer;
    written.clear();
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
      sealer: () async => key,
      pollEvery: const Duration(milliseconds: 5),
      explainTimeout: const Duration(milliseconds: 300),
      renderTimeout: const Duration(milliseconds: 300),
    );
  });

  /// Plays the PC: opens every request and answers it with [answer]
  /// (sealed unless [seal] is false) after a few polls.
  void pcAnswers(
    Map<String, Object?> Function(Map<String, Object?>) answer, {
    bool seal = true,
  }) {
    db.onPut = (path, value) {
      final rid = RegExp(r'^sufler/requests/(.+)$').firstMatch(path)?[1];
      if (rid == null) return;
      Timer(const Duration(milliseconds: 20), () async {
        final req = await sealer.open(path, value! as Map<String, Object?>);
        final out = {...answer(req), 'at': db.serverMs};
        final resultPath = 'sufler/results/$rid';
        final stored = seal ? await sealer.sealResult(resultPath, out) : out;
        written.add(stored);
        db
          ..write(resultPath, stored)
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

  test('a published request carries no script text', () async {
    final published = <String>[];
    pcAnswers((_) => {'ok': true, 'text': 'ok'});
    final pc = db.onPut!;
    db.onPut = (path, value) {
      published.add(jsonEncode(value));
      pc(path, value);
    };
    await relay.explain(script: fixtureScript(), index: 1, selection: 'Wilku');
    expect(published, hasLength(1));
    for (final plain in ['Wilku', 'Dzień dobry', 'Krasnale testowe']) {
      expect(published.single, isNot(contains(plain)));
    }
    final stored = jsonDecode(published.single) as Map<String, Object?>;
    expect(stored.keys, unorderedEquals(['kind', 'deviceId', 'ts', '_e2e']));
  });

  test('a stored result carries no answer text or clip', () async {
    pcAnswers((_) => {'ok': true, 'text': 'Znaczy: dzień dobry.'});
    await relay.explain(script: fixtureScript(), index: 1, selection: 'x');
    final result = written.single! as Map;
    expect(result.keys, unorderedEquals(['ok', 'at', '_e2e']));
    expect(jsonEncode(result), isNot(contains('dzień')));
  });

  test('locked: throws and sends nothing at all', () async {
    key = null;
    await expectLater(
      relay.explain(script: fixtureScript(), index: 1, selection: 'x'),
      throwsA(
        isA<AssistantError>().having((e) => e.message, 'm', contains('kłódka')),
      ),
    );
    expect(await relay.renderLine(script: fixtureScript(), index: 2), isNull);
    expect(db.log, isEmpty);
  });

  test('an unsealed result (an older PC) is still read', () async {
    pcAnswers((_) => {'ok': true, 'text': 'stary PC'}, seal: false);
    expect(
      await relay.explain(script: fixtureScript(), index: 1, selection: 'x'),
      'stary PC',
    );
  });

  test('a result that does not open is an error, never shown', () async {
    // Sealed under another key: does not open with this phone's.
    final other = RelaySealer(E2eCipher(List.filled(32, 9)));
    db.onPut = (path, value) {
      final rid = RegExp(r'^sufler/requests/(.+)$').firstMatch(path)![1];
      final at = 'sufler/results/$rid';
      unawaited(
        other
            .sealResult(at, {'ok': true, 'text': 'x'})
            .then((r) => db.write(at, r)),
      );
    };
    await expectLater(
      relay.explain(script: fixtureScript(), index: 1, selection: 'x'),
      throwsA(
        isA<AssistantError>().having((e) => e.message, 'm', contains('nieczy')),
      ),
    );
  });

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
        sealer: () async => sealer,
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
      await pumpEventQueue();
      expect(seen, [true, false, false]);
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
