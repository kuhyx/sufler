import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/script.dart';

/// Strings the user or the script supplied: the app only displays them, so
/// they may hold words (textgate CONTENT). Everything else painted is chrome.
List<String> scriptContent(Script s) => [
  s.title,
  s.source,
  for (final c in s.characters) c.name,
  for (final x in [...s.scenes, ...s.songs]) x.title,
  for (final l in s.lines) l.text,
];

final _word = RegExp(r'\p{L}{2,}', unicode: true);

/// False when an ancestor hides [ro]: zero opacity or offstage.
bool _painted(RenderObject ro) {
  for (RenderObject? r = ro; r != null; r = r.parent) {
    if (r is RenderOpacity && r.opacity == 0) return false;
    if (r is RenderAnimatedOpacity && r.opacity.value == 0) return false;
    if (r is RenderOffstage && r.offstage) return false;
  }
  return ro is RenderBox && ro.hasSize && !ro.size.isEmpty;
}

/// Painted strings holding a word once [content] is cut out of them.
List<String> paintedWords(Iterable<String> content) {
  final cut = [...content.where((c) => c.isNotEmpty)]
    ..sort((a, b) => b.length.compareTo(a.length));
  final out = <String>[];
  for (final e in find.byType(RichText).evaluate()) {
    final ro = e.renderObject;
    if (ro == null || !ro.attached || !_painted(ro)) continue;
    // Typed field values are user content.
    if (e.findAncestorWidgetOfExactType<EditableText>() != null) continue;
    var s = (e.widget as RichText).text.toPlainText();
    for (final c in cut) {
      s = s.replaceAll(c, ' ');
    }
    if (_word.hasMatch(s)) out.add((e.widget as RichText).text.toPlainText());
  }
  return out;
}

/// Fails when anything painted on [screen] carries a word that is not
/// [content] (textgate: kuhy sees no chrome text).
void expectNoWords(String screen, [Iterable<String> content = const []]) {
  final w = paintedWords(content);
  // ignore: avoid_print
  if (const bool.fromEnvironment('TF_LIST')) return print('TF $screen: $w');
  expect(w, isEmpty, reason: 'words on $screen');
}
