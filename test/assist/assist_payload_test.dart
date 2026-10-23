import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/assist/assist_payload.dart';
import 'package:sufler/model/script.dart';

import '../rehearsal/fixture.dart';

void main() {
  test('explain payload: selection, names, 3 spoken lines before, 1 after', () {
    final body = explainPayload(fixtureScript(), 5, ' dobrze ');
    expect(body, {
      'scriptId': 'abc123',
      'title': 'Krasnale testowe',
      'selection': 'dobrze',
      'line': {
        'index': 5,
        'speakers': ['Błystek'],
        'text': 'No dobrze.',
      },
      'before': [
        {
          'speakers': ['Błystek'],
          'text': 'Dzień dobry, Wilku!',
        },
        {
          'speakers': ['Piaskowy Wilk'],
          'text': 'Piaskowe Wilki nie jedzą Krasnali!',
        },
        {
          'speakers': ['Piaskowy Wilk'],
          'text': 'Naprawdę.',
        },
      ],
      'after': [
        {'speakers': <String>[], 'text': 'La la la'},
      ],
    });
  });

  test('explain payload at the edges of the play', () {
    final first = explainPayload(fixtureScript(), 1, 'Wilku');
    expect(first['before'], isEmpty);
    final script = fixtureScript();
    final last = script.lines.lastWhere((l) => l.isSpoken).index;
    expect(explainPayload(script, last, 'x')['after'], isEmpty);
  });

  test('unknown speaker ids fall back to the id', () {
    final json = fixtureScript().toJson();
    ((json['lines']! as List)[1] as Map)['speakers'] = ['nikt'];
    final body = explainPayload(Script.fromJson(json), 1, 'Wilku');
    expect((body['line']! as Map)['speakers'], ['nikt']);
  });

  test('render_line payload is the bare script plus the index', () {
    final script = fixtureScript();
    expect(renderLinePayload(script, 2), {
      'script': script.toJson(),
      'index': 2,
    });
  });
}
