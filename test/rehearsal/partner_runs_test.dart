import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/controller.dart';
import 'package:sufler/rehearsal/cues.dart';
import 'package:sufler/rehearsal/range.dart';
import 'package:sufler/rehearsal/runs.dart';
import 'package:sufler/rehearsal/session.dart';

import 'controller_test.dart' show FakePlayer;
import 'run_fixture.dart';

ScriptLine _l(int i, List<String> who, String text, {String? song}) =>
    ScriptLine(
      index: i,
      speakers: who,
      text: text,
      kind: song == null ? LineKind.dialogue : LineKind.song,
      sceneId: 's',
      songId: song,
    );

/// Błystek sings four verses (with a chorus verse among them), the Wolf
/// answers; then Błystek speaks three lines in a row, then two.
Script _script() => Script(
  id: 'p',
  title: 'p',
  source: 'p',
  characters: const [
    Character(id: wolf, name: 'Piaskowy Wilk'),
    Character(id: elf, name: 'Błystek'),
  ],
  scenes: const [Section(id: 's', title: 'Scena', start: 0, end: 10)],
  songs: const [Section(id: 'pb', title: 'Piosenka Błystka', start: 0, end: 3)],
  lines: [
    _l(0, [elf], 'Pierwszy wers', song: 'pb'),
    _l(1, [elf], 'Drugi wers', song: 'pb'),
    _l(2, [], 'Refren chóru', song: 'pb'),
    _l(3, [elf], 'Czwarty wers', song: 'pb'),
    _l(4, [wolf], 'Ładna piosenka.'),
    _l(5, [elf], 'Raz.'),
    _l(6, [elf], 'Dwa.'),
    _l(7, [elf], 'Trzy.'),
    _l(8, [wolf], 'No i co?'),
    _l(9, [elf], 'Cztery.'),
    _l(10, [elf], 'Pięć.'),
  ],
);

final _roles = {const Role.character(wolf)};

List<Cue> _cues() {
  final s = _script();
  return mergeRuns(
    buildCues(s, _roles, const LineRange(0, 10)),
    rehearsalRuns(s, _roles),
  );
}

void main() {
  test('a partner song and a 3-line partner speech are one step each', () {
    expect(
      [
        for (final c in _cues())
          '${c.lines.map((l) => l.index).join(',')} ${c.mine}',
      ],
      [
        '0,1,2,3 false',
        '4 true',
        '5,6,7 false',
        '8 true',
        '9 false',
        '10 false',
      ],
    );
  });

  test('next after the song lands on the own line', () {
    final s = RehearsalSession(_cues());
    expect(s.current!.lines, hasLength(4));
    s.partnerDone();
    expect(s.phase, Phase.mine);
    expect(s.current!.line.index, 4);
    s.back();
    expect(s.current!.lines, hasLength(4), reason: 'back over the whole unit');
    s.skip();
    expect(s.current!.line.index, 4);
  });

  test('the song plays every verse back to back, then my line', () {
    fakeAsync((fa) {
      final p = FakePlayer(seconds: 1);
      final c = RehearsalController(RehearsalSession(_cues()), p)..start();
      fa.elapse(const Duration(milliseconds: 3500));
      expect(p.played, [0, 1, 2, 3]);
      expect(c.session.phase, Phase.partner);
      fa.elapse(const Duration(milliseconds: 600));
      expect(c.session.phase, Phase.mine);
      expect(c.session.current!.line.index, 4);
      c.dispose();
    });
  });

  test('a retry after ✗ replays only the last line of the unit before', () {
    fakeAsync((fa) {
      final p = FakePlayer(seconds: 1);
      final c = RehearsalController(
        RehearsalSession(_cues(), selfGrade: true),
        p,
      )..start();
      fa.elapse(const Duration(seconds: 4));
      c
        ..done()
        ..grade(ok: false);
      expect(c.session.phase, Phase.prompt);
      expect(c.session.prompt!.lines, hasLength(1));
      fa.elapse(const Duration(seconds: 2));
      expect(p.played, [0, 1, 2, 3, 3]);
      c.dispose();
    });
  });
}
