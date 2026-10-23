import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/edits.dart';

import 'fixture.dart';

void main() {
  final script = fixtureScript();

  test('editLine replaces speakers and kind of one line', () {
    final out = editLine(script, 3, speakers: [wolf], kind: LineKind.dialogue);
    expect(out.lines[3].speakers, [wolf]);
    expect(out.lines[3].kind, LineKind.dialogue);
    expect(out.lines[2], same(script.lines[2]));
    expect(out.id, script.id);
  });

  test('mergeCharacter folds A into B: lines, cast, aliases', () {
    final out = mergeCharacter(script, from: elf, into: wolf);
    expect(out.characters.map((c) => c.id), [wolf]);
    expect(out.characters.single.aliases, ['Błystek']);
    expect(out.lines[1].speakers, [wolf]);
    // Multi-speaker line does not list the wolf twice.
    expect(out.lines[10].speakers, [wolf]);
    expect(out.toJson()['scenes'], script.toJson()['scenes']);
  });

  test('merging into self is a no-op', () {
    expect(mergeCharacter(script, from: wolf, into: wolf), same(script));
  });

  test('renameRoles moves picked roles after a merge', () {
    final roles = {const Role.character(elf), const Role.song('piosenka')};
    expect(renameRole(roles, from: elf, into: wolf), {
      const Role.character(wolf),
      const Role.song('piosenka'),
    });
  });

  test('roleOptions lists characters and songs with spoken line counts', () {
    final opts = roleOptions(script);
    expect(
      [for (final o in opts) '${o.role} ${o.label} ${o.count}'],
      [
        'character:piaskowy-wilk Piaskowy Wilk 3',
        'character:blystek Błystek 4',
        'song:piosenka Piosenka 3',
      ],
    );
  });
}
