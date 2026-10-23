import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/storage/prefs.dart';

void main() {
  test('rehearsal prefs use the DOCS-contract shape', () {
    final p = RehearsalPrefs(
      roles: {
        const Role.character('piaskowy-wilk'),
        const Role.song('piosenka'),
      },
      speed: 1.5,
      lineSeconds: const {4: 4.2},
      recordings: const {4: 'rec/abc/4'},
    );
    final json = p.toJson();
    expect(json, {
      'roles': ['character:piaskowy-wilk', 'song:piosenka'],
      'speed': 1.5,
      'lineSeconds': {'4': 4.2},
      'recordings': {'4': 'rec/abc/4'},
    });
    final back = RehearsalPrefs.fromJson(json);
    expect(back.roles, p.roles);
    expect(back.speed, 1.5);
    expect(back.lineSeconds, {4: 4.2});
    expect(back.recordings, {4: 'rec/abc/4'});
  });

  test('missing fields fall back to defaults; ints read as doubles', () {
    final p = RehearsalPrefs.fromJson({
      'speed': 2,
      'lineSeconds': {'1': 3},
    });
    expect(p.roles, isEmpty);
    expect(p.speed, 2.0);
    expect(p.lineSeconds, {1: 3.0});
    expect(p.recordings, isEmpty);
  });

  test('copyWith replaces only what is given', () {
    const p = RehearsalPrefs();
    final q = p.copyWith(speed: 3);
    expect(q.speed, 3);
    expect(q.roles, isEmpty);
    final r = q.copyWith(
      roles: {const Role.character('a')},
      lineSeconds: {1: 2},
      recordings: {1: 'k'},
    );
    expect(r.speed, 3);
    expect(r.lineSeconds, {1: 2});
    expect(r.recordings, {1: 'k'});
  });

  test('app settings round trip with defaults', () {
    const s = AppSettings();
    expect(s.visibility, TextVisibility.show);
    expect(s.cleanTarget, 3);
    final t = s.copyWith(
      visibility: TextVisibility.revealAfter,
      selfGrade: true,
      loop: true,
      cleanTarget: 5,
    );
    final back = AppSettings.fromJson(t.toJson());
    expect(back.visibility, TextVisibility.revealAfter);
    expect(back.selfGrade, isTrue);
    expect(back.loop, isTrue);
    expect(back.cleanTarget, 5);
    expect(AppSettings.fromJson(const {}).loop, isFalse);
  });
}
