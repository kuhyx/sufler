import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/rehearsal/partner_player.dart';
import 'package:sufler/rehearsal/timing.dart';
import 'package:sufler/rehearsal/voices.dart';

import '../storage/pack_zip_test.dart' show fixturePackZip;
import 'fixture.dart';

class _Speech implements Speech {
  final said = <(String, Voice, double)>[];
  int stops = 0;
  @override
  Future<void> speak(String text, Voice voice, double speed) async =>
      said.add((text, voice, speed));
  @override
  Future<void> stop() async => stops++;
}

/// A device with no usable voice (Chromium without speech-dispatcher).
class _Mute implements Speech {
  @override
  Future<void> speak(String text, Voice voice, double speed) async =>
      throw const SpeechFailure('synthesis-failed');
  @override
  Future<void> stop() async {}
}

class _Clips implements ClipPlayer {
  final played = <(Uint8List, String)>[];
  int stops = 0;
  @override
  Future<void> play(Uint8List bytes, String mimeType) async =>
      played.add((bytes, mimeType));
  @override
  Future<void> stop() async => stops++;
}

void main() {
  final script = fixtureScript();

  test('uses the pack clip when there is one, TTS otherwise', () async {
    final speech = _Speech();
    final clips = _Clips();
    final p = PartnerPlayer(
      script: script,
      speech: speech,
      clips: clips,
      pack: AudioPack.fromZip(fixturePackZip()),
      speed: 1.5,
    );
    await p.play(script.lines[1]); // has clip
    await p.play(script.lines[5]); // no clip -> TTS
    expect(clips.played.single.$1, [1, 1]);
    expect(clips.played.single.$2, 'audio/ogg');
    expect(speech.said.single.$1, 'No dobrze.');
    expect(speech.said.single.$2, voiceFor(script, script.lines[5]));
    expect(speech.said.single.$3, 1.5);
    await p.stop();
    expect(speech.stops, 1);
    expect(clips.stops, 1);
  });

  test('without a pack everything goes through TTS', () async {
    final speech = _Speech();
    final p = PartnerPlayer(script: script, speech: speech, clips: _Clips());
    var held = 0;
    await p.play(script.lines[1], onHeld: () => held++);
    expect(speech.said.single.$1, 'Dzień dobry, Wilku!');
    expect(held, 0);
  });

  test('when speech fails, the partner text is held for its reading time '
      'instead of being skipped at once', () {
    fakeAsync((clock) {
      final line = script.lines[5];
      final p = PartnerPlayer(
        script: script,
        speech: _Mute(),
        clips: _Clips(),
        speed: 2,
      );
      var done = false;
      var held = 0;
      unawaited(p.play(line, onHeld: () => held++).then((_) => done = true));
      clock.flushMicrotasks();
      // Told at once, so the text can be shown for the whole hold.
      expect(held, 1);
      final hold = defaultPauseSeconds(line.text, speed: 2);
      clock.elapse(Duration(milliseconds: (hold * 1000).round() - 50));
      expect(done, isFalse);
      clock.elapse(const Duration(milliseconds: 100));
      expect(done, isTrue);
    });
  });
}
