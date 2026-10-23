import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/assist/pc_session.dart';
import 'package:sufler/ui/pc_session_tile.dart';

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

Future<void> _pump(WidgetTester tester, PcSession session) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: PcSessionTile(session: session)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signed out: one tap signs in and says so', (tester) async {
    final s = _Session();
    await _pump(tester, s);
    expect(find.textContaining('Zaloguj się'), findsOneWidget);
    await tester.tap(find.text('Połącz'));
    await tester.pumpAndSettle();
    expect(s.signIns, 1);
    expect(find.textContaining('Połączono'), findsOneWidget);
    expect(find.text('Połącz'), findsNothing);
  });

  testWidgets('a failed sign-in keeps the button and explains', (tester) async {
    final s = _Session()..works = false;
    await _pump(tester, s);
    await tester.tap(find.text('Połącz'));
    await tester.pumpAndSettle();
    expect(find.text('Połącz'), findsOneWidget);
    expect(find.textContaining('nie powiodło się'), findsOneWidget);
  });

  testWidgets('already signed in: no button', (tester) async {
    await _pump(tester, _Session()..session = true);
    expect(find.textContaining('Połączono'), findsOneWidget);
    expect(find.text('Połącz'), findsNothing);
  });
}
