import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/rehearsal/cues.dart';
import 'package:sufler/rehearsal/range.dart';

import 'fixture.dart';

List<(int, bool)> _walk(List<Cue> cues) => [
  for (final c in cues) (c.line.index, c.mine),
];

void main() {
  final script = fixtureScript();

  test('walks spoken lines only; consecutive own lines each get a pause', () {
    final cues = buildCues(script, {
      const Role.character(wolf),
    }, LineRange.section(script.scenes[0]));
    // 0 heading and 3 direction are skipped; 2 and 4 are consecutive cues.
    expect(_walk(cues), [(1, false), (2, true), (4, true), (5, false)]);
    expect(cues[1].seconds, greaterThan(0));
    expect(cues[2].seconds, greaterThan(0));
  });

  test('songs as roles own every lyric line regardless of speakers', () {
    final cues = buildCues(script, {
      const Role.song('piosenka'),
    }, LineRange.section(script.songs[0]));
    expect(_walk(cues), [(7, true), (8, true), (9, true)]);
  });

  test('song + character roles combine; multi-speaker line is mine', () {
    final cues = buildCues(script, {
      const Role.song('piosenka'),
      const Role.character(wolf),
    }, LineRange.section(script.scenes[1]));
    expect(_walk(cues), [(7, true), (8, true), (9, true), (10, true)]);
  });

  test('cumulative range runs from the start up to the chosen line', () {
    final cues = buildCues(script, {
      const Role.character(wolf),
    }, LineRange.cumulative(upTo: 7));
    expect(_walk(cues).map((c) => c.$1), [1, 2, 4, 5, 7]);
    final fromSection = buildCues(script, {
      const Role.character(wolf),
    }, LineRange.cumulative(from: 6, upTo: 10));
    expect(_walk(fromSection).map((c) => c.$1), [7, 8, 9, 10]);
  });

  test('custom range is inclusive and order-insensitive, clamped', () {
    expect(LineRange.custom(5, 2), const LineRange(2, 5));
    final cues = buildCues(script, {
      const Role.character(elf),
    }, const LineRange(4, 99));
    expect(_walk(cues).first, (4, false));
    expect(_walk(cues).last, (10, true));
  });

  test('pause uses overrides and recordings via timing', () {
    final cues = buildCues(
      script,
      {const Role.character(wolf)},
      const LineRange(4, 4),
      speed: 1,
      overrides: const {4: 9},
    );
    expect(cues.single.seconds, 9);
  });

  test('range equality and description', () {
    expect(const LineRange(1, 2), isNot(const LineRange(1, 3)));
    expect(const LineRange(1, 2).hashCode, const LineRange(1, 2).hashCode);
    expect(const LineRange(1, 2).toString(), 'LineRange(1..2)');
  });
}
