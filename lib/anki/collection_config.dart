/// Builds the JSON blobs stored in `col.models`, `col.decks`, `col.conf` and
/// `col.dconf`.
///
/// Anki keeps these as JSON text inside the collection row rather than as
/// tables, so they are constructed here and encoded once.
library;

import 'dart:convert';

import 'package:sufler/anki/collection_schema.dart';

/// Returns the `col.models` JSON: a single note type keyed by [modelId].
///
/// The card asks cue -> line. `sortf: 0` sorts by `Cue`, which matches
/// `notes.sfld` being the first field. [defaultDeck] is the deck new notes of
/// this type default to in Anki's "Add" dialog.
String buildModelsJson({required int defaultDeck}) {
  final fields = <Map<String, Object?>>[
    for (var i = 0; i < fieldNames.length; i++)
      <String, Object?>{
        'name': fieldNames[i],
        'ord': i,
        'sticky': false,
        'rtl': false,
        'font': 'Arial',
        'size': 20,
        'media': <String>[],
      },
  ];

  final model = <String, Object?>{
    'id': modelId,
    'name': 'sufler',
    'type': 0,
    'mod': 0,
    'usn': -1,
    'sortf': 0,
    'did': defaultDeck,
    'tmpls': <Map<String, Object?>>[
      <String, Object?>{
        'name': 'Cue -> Line',
        'ord': 0,
        'qfmt': '{{Cue}}',
        'afmt':
            '{{FrontSide}}\n\n<hr id=answer>\n\n<div class=line>{{Line}}</div>',
        'bqfmt': '',
        'bafmt': '',
        'did': null,
        'bfont': '',
        'bsize': 0,
      },
    ],
    'flds': fields,
    'css':
        '.card { font-family: arial; font-size: 20px; text-align: center; '
        'color: black; background-color: white; }\n'
        '.line { font-size: 22px; font-weight: bold; margin-top: 8px; }',
    'latexPre': '',
    'latexPost': '',
    'latexsvg': false,
    'req': <List<Object?>>[
      <Object?>[
        0,
        'any',
        <int>[0],
      ],
    ],
    'tags': <String>[],
    'vers': <String>[],
  };

  return jsonEncode(<String, Object?>{'$modelId': model});
}

/// Returns the `col.decks` JSON for [decks] (deck id -> full name).
///
/// Always carries Anki's default deck `"1"` too: a collection missing it is
/// rejected by some importers.
String buildDecksJson(Map<int, String> decks) {
  Map<String, Object?> deck(int id, String name) => <String, Object?>{
    'id': id,
    'name': name,
    'mod': 0,
    'usn': -1,
    'lrnToday': <int>[0, 0],
    'revToday': <int>[0, 0],
    'newToday': <int>[0, 0],
    'timeToday': <int>[0, 0],
    'collapsed': false,
    'browserCollapsed': false,
    'desc': '',
    'dyn': 0,
    'conf': 1,
    'extendNew': 10,
    'extendRev': 50,
  };

  return jsonEncode(<String, Object?>{
    '$defaultDeckId': deck(defaultDeckId, 'Default'),
    for (final e in decks.entries) '${e.key}': deck(e.key, e.value),
  });
}

/// Returns the `col.conf` JSON: collection-wide preferences.
String buildConfJson() => jsonEncode(<String, Object?>{
  'activeDecks': <int>[defaultDeckId],
  'addToCur': true,
  'collapseTime': 1200,
  'curDeck': defaultDeckId,
  'curModel': '$modelId',
  'dueCounts': true,
  'estTimes': true,
  'newBury': true,
  'newSpread': 0,
  'nextPos': 1,
  'sortBackwards': false,
  'sortType': 'noteFld',
  'timeLim': 0,
});

/// Returns the `col.dconf` JSON: the default deck options group.
String buildDconfJson() => jsonEncode(<String, Object?>{
  '1': <String, Object?>{
    'id': 1,
    'name': 'Default',
    'mod': 0,
    'usn': -1,
    'maxTaken': 60,
    'autoplay': true,
    'timer': 0,
    'replayq': true,
    'new': <String, Object?>{
      'bury': false,
      'delays': <double>[1, 10],
      'initialFactor': 2500,
      'ints': <int>[1, 4, 7],
      'order': 1,
      'perDay': 20,
    },
    'rev': <String, Object?>{
      'bury': false,
      'ease4': 1.3,
      'ivlFct': 1,
      'maxIvl': 36500,
      'perDay': 200,
      'hardFactor': 1.2,
    },
    'lapse': <String, Object?>{
      'delays': <double>[10],
      'leechAction': 1,
      'leechFails': 8,
      'minInt': 1,
      'mult': 0,
    },
    'dyn': false,
  },
});
