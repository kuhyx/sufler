import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sufler/assist/rtdb_client.dart';

RtdbClient _client(List<http.Request> seen, {String? namespace}) => RtdbClient(
  databaseUrl: 'https://db/',
  idToken: () async => 'tok',
  namespace: namespace,
  httpClient: MockClient((r) async {
    seen.add(r);
    return http.Response('null', 200);
  }),
);

Future<List<String>> _paths({String? namespace}) async {
  final seen = <http.Request>[];
  final c = _client(seen, namespace: namespace);
  await c.get('sufler/state');
  await c.put('/sufler/requests/r1/', 1);
  await c.delete('sufler/requests/r1');
  return seen.map((r) => r.url.path).toList();
}

void main() {
  test('empty namespace keeps every path byte-identical', () async {
    expect(await _paths(namespace: ''), [
      '/sufler/state.json',
      '/sufler/requests/r1.json',
      '/sufler/requests/r1.json',
    ]);
  });

  test('a sandbox namespace prefixes every request path', () async {
    expect(
      await _paths(namespace: 'sandbox/slot3'),
      everyElement(startsWith('/sandbox/slot3/sufler/')),
    );
  });

  test('an invalid namespace fails closed at construction', () {
    for (final bad in ['slot3', 'sandbox/', 'sandbox/Slot', '/x', 'a\n']) {
      expect(() => _client([], namespace: bad), throwsException, reason: bad);
    }
  });

  test('the compiled define defaults to empty (production paths)', () async {
    expect(await _paths(), [
      '/sufler/state.json',
      '/sufler/requests/r1.json',
      '/sufler/requests/r1.json',
    ]);
  });
}
