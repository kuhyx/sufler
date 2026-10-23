import 'package:flutter/foundation.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/range.dart';
import 'package:sufler/rehearsal/timing.dart';

/// One step of a rehearsal: a partner line to play, or one of mine to say.
@immutable
class Cue {
  /// Creates a cue.
  const Cue({required this.line, required this.mine, required this.seconds});

  /// The script line.
  final ScriptLine line;

  /// True when the actor says this line (a pause), false for a partner line.
  final bool mine;

  /// Pause length for my lines (also computed for partner lines; unused).
  final double seconds;
}

/// Spoken lines of [range] in reading order, split into mine and partner.
List<Cue> buildCues(
  Script script,
  Set<Role> roles,
  LineRange range, {
  double speed = 1,
  Map<int, double> overrides = const {},
  Map<int, double> recordingSeconds = const {},
}) {
  final last = range.end.clamp(-1, script.lines.length - 1);
  return [
    for (var i = range.start.clamp(0, script.lines.length); i <= last; i++)
      if (script.lines[i].isSpoken)
        Cue(
          line: script.lines[i],
          mine: isMine(script.lines[i], roles),
          seconds: pauseSeconds(
            index: i,
            text: script.lines[i].text,
            speed: speed,
            overrides: overrides,
            recordingSeconds: recordingSeconds,
          ),
        ),
  ];
}
