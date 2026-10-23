import 'package:sufler/model/script.dart';

/// Polish name of a line kind.
String kindLabel(LineKind kind) => switch (kind) {
  LineKind.dialogue => 'dialog',
  LineKind.song => 'piosenka',
  LineKind.recitation => 'recytacja',
  LineKind.direction => 'didaskalia',
  LineKind.heading => 'nagłówek',
};

/// Display names of [line]'s speakers ("Chór" when unattributed).
String speakerNames(Script script, ScriptLine line) {
  if (line.speakers.isEmpty) return 'Chór';
  return [
    for (final id in line.speakers)
      script.characters
          .firstWhere(
            (c) => c.id == id,
            orElse: () => Character(id: id, name: id),
          )
          .name,
  ].join(', ');
}

/// Seconds with one decimal and a Polish decimal comma ("7,4 s").
String seconds(double s) => '${s.toStringAsFixed(1).replaceAll('.', ',')} s';

/// Breakpoint between phone (one column) and desktop (two columns).
const double wideLayout = 840;
