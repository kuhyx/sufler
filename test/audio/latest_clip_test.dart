import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/audio/latest_clip.dart';

/// An output whose `start` calls resolve only when the test says so, in any
/// order: what a slow platform player does when steps are skipped fast. A
/// start takes effect when it resolves (logged then); a halt at once.
class _SlowOutput implements ClipOutput {
  final log = <String>[];
  final calls = <String>[];
  final pending = <String, Completer<void>>{};
  final _done = StreamController<void>.broadcast();

  /// What the output plays now: the last start not halted since.
  String? get playing {
    String? now;
    for (final e in log) {
      now = e.startsWith('start ') ? e.substring(6) : null;
    }
    return now;
  }

  @override
  Future<void> start(Uint8List bytes, String mimeType) {
    final name = String.fromCharCodes(bytes);
    calls.add(name);
    final c = pending[name] = Completer<void>();
    return c.future.then((_) => log.add('start $name'));
  }

  @override
  Future<void> halt() async => log.add('halt');

  @override
  Stream<void> get completed => _done.stream;

  void finish() => _done.add(null);
}

Uint8List _clip(String name) => Uint8List.fromList(name.codeUnits);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'a clip superseded while starting never lands on the newer one',
    () async {
      final out = _SlowOutput();
      final player = LatestClipPlayer(out);
      var aDone = false;
      unawaited(player.play(_clip('A'), 'audio/ogg').then((_) => aDone = true));
      await _settle();
      var bDone = false;
      unawaited(player.play(_clip('B'), 'audio/ogg').then((_) => bDone = true));
      await _settle();
      // B waits for A's start to come back before it touches the output.
      expect(out.calls, ['A']);
      out.pending['A']!.complete();
      await _settle();
      expect(aDone, isTrue, reason: 'the superseded play returns');
      expect(out.calls, ['A', 'B']);
      expect(out.playing, isNull, reason: 'A was halted before B starts');
      out.pending['B']!.complete();
      await _settle();
      expect(out.playing, 'B');
      expect(bDone, isFalse, reason: 'B plays until it ends');
      out.finish();
      await _settle();
      expect(bDone, isTrue);
    },
  );

  test(
    'a newer start resolving first is not undone by the older one',
    () async {
      final out = _SlowOutput();
      final player = LatestClipPlayer(out);
      unawaited(player.play(_clip('A'), 'audio/ogg'));
      await _settle();
      unawaited(player.play(_clip('B'), 'audio/ogg'));
      unawaited(player.play(_clip('C'), 'audio/ogg'));
      await _settle();
      out.pending['A']!.complete();
      await _settle();
      // B was superseded by C before its turn: it never starts.
      expect(out.calls, ['A', 'C']);
      out.pending['C']!.complete();
      await _settle();
      expect(out.playing, 'C');
    },
  );

  test('stop while a clip is starting leaves the output silent', () async {
    final out = _SlowOutput();
    final player = LatestClipPlayer(out);
    var done = false;
    unawaited(player.play(_clip('A'), 'audio/ogg').then((_) => done = true));
    await _settle();
    final stopped = player.stop();
    await _settle();
    out.pending['A']!.complete();
    await stopped;
    await _settle();
    expect(done, isTrue);
    expect(out.playing, isNull);
  });

  test('a clip that plays to its end completes', () async {
    final out = _SlowOutput();
    final player = LatestClipPlayer(out);
    var done = false;
    unawaited(player.play(_clip('A'), 'audio/ogg').then((_) => done = true));
    await _settle();
    out.pending['A']!.complete();
    await _settle();
    expect(done, isFalse);
    out.finish();
    await _settle();
    expect(done, isTrue);
  });
}
