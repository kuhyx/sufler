import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/cues.dart';
import 'package:sufler/rehearsal/range.dart';
import 'package:sufler/rehearsal/runs.dart';
import 'package:sufler/rehearsal/session.dart';

import 'run_fixture.dart';

List<List<int>> _indices(List<LineRun> runs) => [
  for (final r in runs) [for (final l in r.lines) l.index],
];

void main() {
  final script = runScript();
  final roles = {const Role.character(wolf)};
  List<Cue> cues() => buildCues(script, roles, const LineRange(0, 11));

  group('findRuns', () {
    test('a 3-line monologue and a song; a direction does not break', () {
      final runs = findRuns(script, roles);
      expect(_indices(runs), [
        [2, 4, 5],
        [8, 9, 10],
      ]);
      expect(runs[0].songId, isNull);
      expect(runs[1].songId, 'piosenka-wilka');
    });

    test('a partner line breaks a run; two spoken lines are no run', () {
      // Błystek's own lines are 1, 6, 11: never consecutive.
      expect(findRuns(script, {const Role.character(elf)}), isEmpty);
      final cut = Script(
        id: 'x',
        title: 'x',
        source: 'x',
        characters: script.characters,
        scenes: script.scenes,
        songs: const [],
        lines: [
          for (final l in script.lines)
            if (l.index != 5)
              l
            else
              ScriptLine(
                index: 5,
                speakers: const [elf],
                text: l.text,
                kind: l.kind,
                sceneId: l.sceneId,
              ),
        ],
      );
      // 2, 4 then a partner line: too short. The song still counts.
      expect(_indices(findRuns(cut, roles)), [
        [8, 9, 10],
      ]);
    });

    test('a song is its own run: the line before it is not joined', () {
      final run = findRuns(script, roles)[1];
      expect(run.lines.first.index, 8, reason: '7 is spoken, not sung');
    });

    test('a two-verse song is a run, a two-line speech is not', () {
      final short = Script(
        id: 'y',
        title: 'y',
        source: 'y',
        characters: script.characters,
        scenes: script.scenes,
        songs: script.songs,
        lines: [
          for (final l in script.lines)
            if (l.index == 10 || l.index == 5)
              ScriptLine(
                index: l.index,
                speakers: const [elf],
                text: l.text,
                kind: l.kind,
                sceneId: l.sceneId,
                songId: l.songId,
              )
            else
              l,
        ],
      );
      expect(_indices(findRuns(short, roles)), [
        [8, 9],
      ]);
    });
  });

  group('mergeRuns', () {
    test('each run becomes one own cue: all its text, the summed pause', () {
      final plain = cues();
      final merged = mergeRuns(plain, findRuns(script, roles));
      expect([for (final c in merged) c.line.index], [1, 2, 6, 7, 8, 11]);
      final mono = merged[1];
      expect(mono.mine, isTrue);
      expect([for (final l in mono.lines) l.index], [2, 4, 5]);
      expect(
        mono.text,
        'Raz dwa trzy cztery.\nPięć sześć.\nSiedem osiem dziewięć dziesięć.',
      );
      final sum = plain
          .where((c) => const [2, 4, 5].contains(c.line.index))
          .fold<double>(0, (a, c) => a + c.seconds);
      expect(mono.seconds, closeTo(sum, 1e-9));
      expect(merged[3].lines, hasLength(1), reason: 'the lone line 7');
      expect(merged[3].text, 'Teraz piosenka.');
    });

    test('a range cutting a run keeps the part inside it together', () {
      final part = buildCues(script, roles, const LineRange(4, 9));
      final merged = mergeRuns(part, findRuns(script, roles));
      expect(
        [for (final c in merged) c.lines.map((l) => l.index).toList()],
        [
          [4, 5],
          [6],
          [7],
          [8, 9],
        ],
      );
    });

    test('withSeconds keeps the run', () {
      final run = mergeRuns(cues(), findRuns(script, roles))[1];
      expect(withSeconds(run, 9).lines, run.lines);
    });

    test('only missed: a run with any missed line comes whole, cued', () {
      final merged = mergeRuns(cues(), findRuns(script, roles));
      final out = onlyMissed(merged, {9});
      expect(
        [for (final c in out) (c.line.index, c.mine, c.lines.length)],
        [(7, false, 1), (8, true, 3)],
      );
    });
  });

  test('learn: a run is graded once; ✗ replays the cue before it', () {
    final merged = mergeRuns(cues(), findRuns(script, roles));
    final s = RehearsalSession(merged, selfGrade: true)..partnerDone();
    expect(s.phase, Phase.mine);
    expect(s.current!.lines, hasLength(3));
    s.finishPause();
    expect(s.grade(ok: false), isTrue);
    expect(s.phase, Phase.prompt);
    expect(s.prompt!.line.index, 1);
    s
      ..partnerDone()
      ..finishPause();
    expect(s.retry, isTrue);
    expect(s.grade(ok: true), isFalse, reason: 'a retry is not knowledge');
    expect(s.current!.line.index, 6);
    expect(s.results, {1: false});
  });
}
