import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/storage/migrate.dart';
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
      'knowledge': <String, Object?>{},
      'rolesAsked': false,
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
    expect(s.visibility, TextVisibility.revealAfter);
    expect(s.grades, isTrue);
    expect(s.cleanTarget, 3);
    expect(s.partnerText, isFalse);
    final t = s.copyWith(
      partnerText: true,
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
    expect(back.partnerText, isTrue);
    expect(AppSettings.fromJson(const {}).loop, isFalse);
  });

  test('settings saved by v1 move "show" to learning mode, once', () {
    // The exact shape the old settings card wrote: every field, default
    // "show" included, no version key.
    const v1 = {
      'visibility': 'show',
      'selfGrade': false,
      'loop': true,
      'cleanTarget': 4,
    };
    final s = AppSettings.fromJson(v1);
    expect(s.visibility, TextVisibility.revealAfter);
    expect(s.loop, isTrue);
    expect(s.cleanTarget, 4);
    expect(s.lastScriptId, isNull);
    expect(s.partnerText, isFalse);
    expect(
      AppSettings.fromJson({...v1, 'visibility': 'hide'}).visibility,
      TextVisibility.hide,
    );
    // Choosing read-through after the migration sticks.
    final chosen = s.copyWith(visibility: TextVisibility.show).toJson();
    expect(chosen['version'], settingsVersion);
    expect(AppSettings.fromJson(chosen).visibility, TextVisibility.show);
    expect(AppSettings.fromJson({...chosen, 'loop': false}).grades, isFalse);
    final last = AppSettings.fromJson(s.copyWith(lastScriptId: 'x').toJson());
    expect(last.lastScriptId, 'x');
  });

  test('settings saved before "partnerText" keep partner text hidden', () {
    const v2 = {'version': 2, 'visibility': 'show', 'listen': true};
    final s = AppSettings.fromJson(v2);
    expect(s.partnerText, isFalse);
    // Read-through chosen under v2 is not migrated again.
    expect(s.visibility, TextVisibility.show);
    expect(s.listen, isTrue);
  });

  test('prefs from v1 load; knowledge and resume round trip', () {
    final old = RehearsalPrefs.fromJson(const {
      'roles': ['character:a'],
      'speed': 1.0,
      'lineSeconds': {'4': 4.2},
      'recordings': <String, Object?>{},
    });
    expect(old.knowledge, isEmpty);
    expect(old.resume, isNull);
    expect(old.rolesAsked, isFalse);
    var p = old.graded(4, ok: true).graded(4, ok: false).graded(7, ok: true);
    expect(p.missed, {4});
    for (var i = 0; i < knowledgeDepth + 5; i++) {
      p = p.graded(9, ok: i.isEven);
    }
    expect(p.knowledge[9], hasLength(knowledgeDepth));
    p = p.copyWith(
      resume: const ResumePoint(label: 'Scena 1', start: 0, end: 5).at(3),
      rolesAsked: true,
    );
    final back = RehearsalPrefs.fromJson(p.toJson());
    expect(back.knowledge[4], [true, false]);
    expect(back.resume!.position, 3);
    expect(back.resume!.label, 'Scena 1');
    expect(back.resume!.missedOnly, isFalse);
    expect(back.rolesAsked, isTrue);
    expect(back.lineSeconds, {4: 4.2});
    expect(back.copyWith(clearResume: true).resume, isNull);
    const missed = ResumePoint(label: 'x', start: 1, end: 2, missedOnly: true);
    expect(ResumePoint.fromJson(missed.toJson()).missedOnly, isTrue);
    // A ✗ being retried is kept; older points (no key) are not retries.
    expect(back.resume!.retry, isFalse);
    expect(missed.toJson().containsKey('retry'), isFalse);
    final retry = missed.at(1, line: 2, retry: true);
    final r = ResumePoint.fromJson(retry.toJson());
    expect((r.retry, r.position, r.line), (true, 1, 2));
    expect(r.at(2).retry, isFalse);
  });

  test('tapped times: optional, round trip, omitted when empty', () {
    final old = RehearsalPrefs.fromJson(const {
      'lineSeconds': {'4': 4.2},
    });
    expect(old.tapSeconds, isEmpty);
    expect(old.toJson().containsKey('tapSeconds'), isFalse);
    final p = old.copyWith(tapSeconds: {4: 4.2, 7: 1.5});
    expect(RehearsalPrefs.fromJson(p.toJson()).tapSeconds, {4: 4.2, 7: 1.5});
  });

  test('pure runs: optional, round trip, kept through a re-parse', () {
    const old = RehearsalPrefs();
    expect(old.toJson().containsKey('pureRuns'), isFalse);
    expect(RehearsalPrefs.fromJson(const {}).pureRuns, isEmpty);
    final p = old.withPureRun('scena-1').withPureRun('scena-1');
    expect(p.pureRuns, {'scena-1'});
    expect(p.toJson()['pureRuns'], ['scena-1']);
    expect(RehearsalPrefs.fromJson(p.toJson()).pureRuns, {'scena-1'});
    expect(movePrefs(p, const {0: 0}, 1).prefs.pureRuns, {'scena-1'});
  });
}
