import 'dart:convert';
import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart' show E2eKeyCache;
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/assist/relay_seal.dart';
import 'package:sufler/assist/rtdb_client.dart';

import 'fake_rtdb.dart';

/// Header, passphrase and records sealed by the PC (`python`) and by this
/// app (`dart`); `tts/tests/test_relay_e2e.py` reads the same file.
final Map<String, Object?> vectors = jsonDecode(
  File('test/assist/relay_e2e_vectors.json').readAsStringSync(),
) as Map<String, Object?>;

void main() {
  late FakeRtdb db;
  late RtdbClient rtdb;
  String? passphrase;
  List<int>? cached;
  late int cacheWrites;

  RelayKey newKey() => RelayKey(
    rtdb: rtdb,
    readPassphrase: () async => passphrase,
    cache: E2eKeyCache(
      read: () async => cached,
      write: (bytes) async {
        cacheWrites++;
        cached = bytes;
      },
    ),
  );

  setUp(() {
    db = FakeRtdb();
    rtdb = RtdbClient(
      databaseUrl: 'https://db.example/',
      idToken: () async => 'tok',
      httpClient: db.client,
      namespace: '',
    );
    passphrase = vectors['passphrase']! as String;
    cached = null;
    cacheWrites = 0;
  });

  test('no header yet: locked, and the phone never writes one', () async {
    final key = newKey();
    expect(await key.sealer(), isNull);
    expect(key.locked.value, isTrue);
    expect(db.log.where((l) => l.startsWith('PUT')), isEmpty);
    // The PC wrote it meanwhile: the next try opens (locked is not cached).
    db.write('sufler/e2e', vectors['header']);
    expect(await key.sealer(), isNotNull);
    expect(key.locked.value, isFalse);
  });

  test('the PC header + passphrase open its records; key cached', () async {
    db.write('sufler/e2e', vectors['header']);
    final sealer = (await newKey().sealer())!;
    final rid = vectors['rid']! as String;
    final plain = vectors['plain']! as Map<String, Object?>;
    for (final side in ['python', 'dart']) {
      final sealed = vectors[side]! as Map<String, Object?>;
      expect(
        await sealer.open(
          'sufler/requests/$rid',
          (sealed['request']! as Map).cast(),
        ),
        plain['request'],
      );
      expect(
        await sealer.open(
          'sufler/results/$rid',
          (sealed['result']! as Map).cast(),
        ),
        plain['result'],
      );
    }
    expect(cacheWrites, 1);
    passphrase = null; // a restart opens from the keystore cache alone
    expect(await newKey().sealer(), isNotNull);
    expect(cacheWrites, 1);
  });

  test('no passphrase, a wrong one, or a bad header: locked', () async {
    db.write('sufler/e2e', vectors['header']);
    passphrase = null;
    expect(await newKey().sealer(), isNull);
    passphrase = 'not it';
    expect(await newKey().sealer(), isNull);
    passphrase = vectors['passphrase']! as String;
    db.write('sufler/e2e', {'v': 1});
    expect(await newKey().sealer(), isNull);
    expect(cacheWrites, 0);
  });

  test('retry drops the key and unlocks again', () async {
    db.write('sufler/e2e', vectors['header']);
    final key = newKey();
    expect(await key.sealer(), isNotNull);
    passphrase = null;
    cached = null;
    expect(await key.retry(), isNull);
    expect(key.locked.value, isTrue);
  });

  test('the header store reads only; writes and deletes are refused', () {
    final store = RelayHeaderStore(rtdb);
    expect(
      () => store.putFileText('sufler/e2e', '{}', message: ''),
      throwsA(anything),
    );
    expect(() => store.deleteFile('sufler/e2e'), throwsA(anything));
    expect(store.listDirectory('x'), completion(isEmpty));
    expect(store.canAccessRemote(), completion(isTrue));
    store.close();
  });
}
