import 'package:crdt_sync_flutter/crdt_sync_flutter.dart'
    show kE2ePassphraseKey, kSecureStorage, keystoreKeyCache;
import 'package:crdt_sync_flutter/testing/fake_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/assist/pc_session.dart';
import 'package:sufler/assist/relay_seal.dart';
import 'package:sufler/assist/rtdb_client.dart';
import 'package:sufler/ui/pc_session_tile.dart';

import '../assist/fake_rtdb.dart';
import '../assist/relay_seal_test.dart' show vectors;
import 'hub.dart';

class _Session implements PcSession {
  bool session = false;
  bool works = true;
  int signIns = 0;

  @override
  Future<bool> signedIn() async => session;

  @override
  Future<bool> signIn() async {
    signIns++;
    session = works;
    return works;
  }
}

Future<void> _pump(
  WidgetTester tester,
  PcSession session, {
  RelayKey? relayKey,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PcSessionTile(session: session, relayKey: relayKey),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signed out: one tap signs in and says so', (tester) async {
    final s = _Session();
    await _pump(tester, s);
    expect(bySpokenContaining('Zaloguj się'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Połącz'));
    await tester.pumpAndSettle();
    expect(s.signIns, 1);
    expect(bySpokenContaining('Połączono'), findsOneWidget);
    expect(find.bySemanticsLabel('Połącz'), findsNothing);
  });

  testWidgets('a failed sign-in keeps the button and explains', (tester) async {
    final s = _Session()..works = false;
    await _pump(tester, s);
    await tester.tap(find.bySemanticsLabel('Połącz'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Połącz'), findsOneWidget);
    expect(bySpokenContaining('nie powiodło się'), findsOneWidget);
  });

  testWidgets('already signed in: no button', (tester) async {
    await _pump(tester, _Session()..session = true);
    expect(bySpokenContaining('Połączono'), findsOneWidget);
    expect(find.bySemanticsLabel('Połącz'), findsNothing);
  });

  testWidgets('signed in, no passphrase: a lock; entering it opens it', (
    tester,
  ) async {
    installFakeSecureStorage();
    final db = FakeRtdb()..write('sufler/e2e', vectors['header']);
    final key = RelayKey(
      rtdb: RtdbClient(
        databaseUrl: 'https://db.example/',
        idToken: () async => 'tok',
        httpClient: db.client,
        namespace: '',
      ),
      readPassphrase: () => kSecureStorage.read(key: kE2ePassphraseKey),
      cache: keystoreKeyCache(relayKeyScope),
    );
    await tester.runAsync(
      () => _pump(tester, _Session()..session = true, relayKey: key),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byIcon(Icons.lock), findsOneWidget);
    await tester.tap(find.byIcon(Icons.lock));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      vectors['passphrase']! as String,
    );
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      while (key.locked.value) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(find.byIcon(Icons.lock_open), findsOneWidget);
    expect(db.log.where((l) => l.startsWith('PUT')), isEmpty);
  });
}
