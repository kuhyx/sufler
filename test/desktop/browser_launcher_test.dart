import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/desktop/browser_launcher.dart';

class _FakeProcess implements Process {
  _FakeProcess(this._exit);
  final Future<int> _exit;
  @override
  Future<int> get exitCode => _exit;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('override wins, then the first existing candidate', () {
    expect(findBrowser(override: '/x/b', exists: (_) => true), '/x/b');
    expect(
      findBrowser(
        override: '',
        exists: (p) => p == '/opt/thorium-browser/thorium-browser',
      ),
      '/opt/thorium-browser/thorium-browser',
    );
    expect(findBrowser(override: '', exists: (_) => false), '');
  });

  test('args: loopback app url, fixed profile, WM class', () {
    final args = browserArgs('/home/u');
    expect(args, contains('--app=http://127.0.0.1:8792'));
    expect(
      args,
      contains('--user-data-dir=/home/u/.local/share/sufler/chrome-profile'),
    );
    expect(args, contains('--class=sufler'));
    expect(kWrapperPort, 8792);
  });

  test('a browser that returns at once is a handoff', () async {
    String? ran;
    final owned = await launchBrowser(
      '/home/u',
      browser: '/b',
      start: (exe, args) async {
        ran = exe;
        return _FakeProcess(Future.value(0));
      },
    );
    expect(ran, '/b');
    expect(owned, isFalse);
  });

  test('no browser: reports and returns false', () async {
    expect(await launchBrowser('/home/u', browser: ''), isFalse);
  });

  test('ran long enough means the window owned the session', () async {
    var t = DateTime(2026);
    final owned = await launchBrowser(
      '/home/u',
      browser: '/b',
      clock: () => t,
      start: (exe, args) async => _FakeProcess(
        Future(() {
          t = t.add(const Duration(seconds: 6));
          return 0;
        }),
      ),
    );
    expect(owned, isTrue);
  });
}
