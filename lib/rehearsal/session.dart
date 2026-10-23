import 'package:sufler/rehearsal/cues.dart';

/// What the rehearsal is waiting for right now.
enum Phase {
  /// A partner line is being played.
  partner,

  /// The actor is saying their line (countdown running).
  mine,

  /// The actor grades the line they just said.
  grade,

  /// The section is over (or the loop target was reached).
  finished,
}

/// Score of one pass through the section.
class PassScore {
  /// Creates a score.
  const PassScore(this.ok, this.total);

  /// Own lines graded correct.
  final int ok;

  /// Own lines in the section.
  final int total;

  /// Every own line was correct.
  bool get clean => ok == total;

  @override
  String toString() => '$ok/$total';
}

/// Pure rehearsal state machine: no timers, no audio. The controller feeds
/// it events ("partner finished", "pause over", a grade, skip, back).
///
/// Loop mode always self-grades: a pass is only clean when every own line
/// was graded correct, and a skipped own line counts as missed.
class RehearsalSession {
  /// Starts at the first cue of pass 1.
  RehearsalSession(
    this.cues, {
    bool selfGrade = false,
    this.loop = false,
    this.cleanTarget = 3,
  }) : grades = selfGrade || loop {
    _enter();
  }

  /// The walk, in order.
  final List<Cue> cues;

  /// Whether a grade step follows each own line.
  final bool grades;

  /// Repeat the section until [cleanTarget] consecutive clean passes.
  final bool loop;

  /// Consecutive clean passes needed to finish in loop mode.
  final int cleanTarget;

  /// Index into [cues].
  int position = 0;

  /// Current pass, 1-based.
  int pass = 1;

  /// Current phase.
  Phase phase = Phase.partner;

  /// Grades of this pass, by cue position.
  final Map<int, bool> results = {};

  /// Finished passes.
  final List<PassScore> history = [];

  /// Consecutive clean passes so far.
  int cleanStreak = 0;

  /// The cue being played or said; null when finished.
  Cue? get current => phase == Phase.finished ? null : cues[position];

  /// Number of own lines in the section.
  int get ownCount => cues.where((c) => c.mine).length;

  void _enter() {
    if (position >= cues.length) {
      _endPass();
      return;
    }
    phase = cues[position].mine ? Phase.mine : Phase.partner;
  }

  void _next() {
    position++;
    _enter();
  }

  void _endPass() {
    final total = ownCount;
    final ok = grades
        ? results.values.where((v) => v).length
        : total; // ungraded passes count as clean
    final score = PassScore(ok, total);
    history.add(score);
    cleanStreak = score.clean ? cleanStreak + 1 : 0;
    if (!loop || cleanStreak >= cleanTarget || cues.isEmpty) {
      phase = Phase.finished;
      return;
    }
    pass++;
    position = 0;
    results.clear();
    _enter();
  }

  /// The partner line finished playing.
  void partnerDone() {
    if (phase == Phase.partner) _next();
  }

  /// The countdown ran out, or the actor tapped "done".
  void finishPause() {
    if (phase != Phase.mine) return;
    if (grades) {
      phase = Phase.grade;
    } else {
      _next();
    }
  }

  /// Self-grade of the line just said.
  void grade({required bool ok}) {
    if (phase != Phase.grade) return;
    results[position] = ok;
    _next();
  }

  /// Jump to the next cue. A skipped own line is recorded as missed.
  void skip() {
    if (phase == Phase.finished) return;
    if (cues[position].mine) results[position] = false;
    _next();
  }

  /// Step back one cue (or replay the first). Clears that cue's grade.
  void back() {
    if (phase == Phase.finished) {
      if (cues.isEmpty) return;
      position = cues.length - 1;
    } else if (position > 0) {
      position--;
    }
    results.remove(position);
    _enter();
  }

  /// Start over from pass 1.
  void restart() {
    position = 0;
    pass = 1;
    results.clear();
    history.clear();
    cleanStreak = 0;
    _enter();
  }
}
