import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/rehearsal/groups.dart';

import 'fixture.dart';
import 'group_fixture.dart';

void main() {
  test('ensembles, plural headings, trios and the chorus are groups', () {
    final s = groupScript();
    final groups = groupOptions(s);
    final byLabel = {for (final g in groups) g.label: g};
    expect(byLabel.keys, [
      'Wszyscy',
      'Śnieżynki',
      'Ala, Bolek, Cela',
      'Chór (kwestie bez przypisania)',
    ]);
    expect(byLabel['Wszyscy']!.role, const Role.character('wszyscy'));
    expect(byLabel['Wszyscy']!.count, 1);
    expect(byLabel['Wszyscy']!.members, contains('wilk'));
    expect(byLabel['Śnieżynki']!.members, {'sniezynka-1', 'sniezynka-2'});
    // The trio's own lines plus the line they say with the wolf.
    final trio = byLabel['Ala, Bolek, Cela']!;
    expect(trio.role, Role.group(['cela', 'ala', 'bolek']));
    expect(trio.count, 4);
    expect(byLabel['Chór (kwestie bez przypisania)']!.count, 1);
    expect(isEnsemble(s, s.characters.first), isFalse);
  });

  test('suggestions follow membership; extra counts stay honest', () {
    final s = groupScript();
    final groups = groupOptions(s);
    final trio = Role.group(['ala', 'bolek', 'cela']);
    expect(suggestedGroups(groups, {'ala'}), {
      const Role.character('wszyscy'),
      trio,
    });
    expect(suggestedGroups(groups, {'wilk'}), {
      const Role.character('wszyscy'),
    });
    expect(suggestedGroups(groups, {'sniezynka-1'}), {
      const Role.character('wszyscy'),
      const Role.character('sniezynki'),
    });
    // Ala already says every trio line: joining the trio adds nothing.
    const ala = Role.character('ala');
    expect(extraLines(s, trio, {ala, trio}), 0);
    expect(extraLines(s, trio, {const Role.character('wilk')}), 3);
    expect(extraLines(s, const Role.character('wszyscy'), {ala}), 1);
  });

  test('a play without group speakers has no groups', () {
    expect(groupOptions(fixtureScript()), [
      (
        role: Role.group(const []),
        label: 'Chór (kwestie bez przypisania)',
        count: 2,
        members: const <String>{},
      ),
    ]);
  });
}
