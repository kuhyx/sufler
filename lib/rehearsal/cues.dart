import 'package:flutter/foundation.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/range.dart';
import 'package:sufler/rehearsal/timing.dart';

/// One step of a rehearsal: a partner line to play, or one of mine to say.
@immutable
class Cue {
  /// Creates a cue.
  const new({
    required this.line,
    required this.mine,
    required this.seconds,
    this.estimated = false,
    this.following = const [],
  });

  /// The script line (the first one of a run).
  final ScriptLine line;

  /// The rest of a run said in one go (`runs.dart`); empty for one line.
  final List<ScriptLine> following;

  /// Every line of the cue, in order.
  List<ScriptLine> get lines => [line, ...following];

  /// Its text: a run's lines one per row.
  String get text => [for (final l in lines) l.text].join('\n');

  /// True when the actor says this line (a pause), false for a partner line.
  final bool mine;

  /// Pause length for my lines (also computed for partner lines; unused).
  final double seconds;

  /// True when [seconds] is guessed from his pace ("szacowane").
  final bool estimated;
}

/// Spoken lines of [range] in reading order, split into mine and partner.
List<Cue> buildCues(
  Script script,
  Set<Role> roles,
  LineRange range, {
  double speed = 1,
  Map<int, double> overrides = const {},
  Map<int, double> recordingSeconds = const {},
  double? pace,
}) {
  final last = range.end.clamp(-1, script.lines.length - 1);
  Cue cue(ScriptLine line) {
    final p = resolvePause(
      index: line.index,
      text: line.text,
      speed: speed,
      overrides: overrides,
      recordingSeconds: recordingSeconds,
      pace: pace,
    );
    return Cue(
      line: line,
      mine: isMine(line, roles),
      seconds: p.seconds,
      estimated: p.source == PauseSource.estimate,
    );
  }

  return [
    for (var i = range.start.clamp(0, script.lines.length); i <= last; i++)
      if (script.lines[i].isSpoken) cue(script.lines[i]),
  ];
}

/// "Only lines I missed": each own cue whose line is in [missed], preceded
/// by the cue before it as its prompt (read out even if it is mine).
List<Cue> onlyMissed(List<Cue> cues, Set<int> missed) {
  final out = <Cue>[];
  for (final (i, cue) in cues.indexed) {
    if (!cue.mine || !cue.lines.any((l) => missed.contains(l.index))) continue;
    if (i > 0 && (out.isEmpty || out.last.line != cues[i - 1].lines.last)) {
      final prompt = lastLineOf(cues[i - 1]);
      out.add(Cue(line: prompt.line, mine: false, seconds: prompt.seconds));
    }
    out.add(cue);
  }
  return out;
}

/// The last line of [cue] alone (a run's cue for what follows it).
Cue lastLineOf(Cue cue) => cue.following.isEmpty
    ? cue
    : Cue(line: cue.lines.last, mine: cue.mine, seconds: cue.seconds);

/// [cue] with a new pause length, set by hand (no longer estimated).
Cue withSeconds(Cue cue, double seconds) => Cue(
  line: cue.line,
  mine: cue.mine,
  seconds: seconds,
  following: cue.following,
);
