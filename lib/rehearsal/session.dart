import 'package:sufler/rehearsal/cues.dart';

/// What the rehearsal is waiting for right now.
enum Phase {
  /// A partner line is being played.
  partner,

  /// The actor is saying their line (countdown running).
  mine,

  /// The actor grades the line they just said.
  grade,

  /// After a ✗: the cue before the line is replayed, then it is asked again.
  prompt,

  /// The section is over (or the loop target was reached).
  finished,
}

/// Score of one pass through the section.
class PassScore {
  /// Creates a score.
  const new(this.ok, this.total);

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
/// was graded correct, and a skipped own line counts as missed. A ✗ does
/// not move on: the cue before the line is replayed and the line is asked
/// again until ✓. Only the first attempt of a pass counts.
class RehearsalSession {
  /// Starts pass 1 at cue [startAt] (0: the beginning; a resumed walk
  /// passes where it stopped).
  new(
    this.cues, {
    bool selfGrade = false,
    this.loop = false,
    this.cleanTarget = 3,
    int startAt = 0,
  }) : grades = selfGrade || loop {
    position = startAt.clamp(0, cues.length);
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

  /// First-attempt grades of this pass, by cue position.
  final Map<int, bool> results = {};

  /// Finished passes.
  final List<PassScore> history = [];

  /// Consecutive clean passes so far.
  int cleanStreak = 0;

  /// Passes finished with every own line ✓ on the first try.
  int purePasses = 0;

  /// The cue replayed before a line graded ✗: the one before it, even if it
  /// is mine (as in "only lines I missed"); null when there is none.
  Cue? get prompt => position > 0 ? cues[position - 1] : null;

  /// The cue being played or said; null when finished.
  Cue? get current => phase == Phase.finished ? null : cues[position];

  /// The current own line was already graded ✗ in this pass: it is being
  /// asked again.
  bool get retry => phase != Phase.finished && results[position] == false;

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
    if (grades && total > 0 && score.clean) purePasses++;
    if (!loop || cleanStreak >= cleanTarget || cues.isEmpty) {
      phase = Phase.finished;
      return;
    }
    pass++;
    position = 0;
    results.clear();
    _enter();
  }

  /// The partner line (or the replayed prompt) finished playing.
  void partnerDone() {
    if (phase == Phase.partner) {
      _next();
    } else if (phase == Phase.prompt) {
      phase = Phase.mine;
    }
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

  /// Self-grade of the line just said; ✗ asks it again (after its
  /// [prompt]). Returns whether this was the line's first attempt.
  bool grade({required bool ok}) {
    if (phase != Phase.grade) return false;
    final first = !results.containsKey(position);
    if (first) results[position] = ok;
    if (ok) {
      _next();
    } else {
      phase = prompt == null ? Phase.mine : Phase.prompt;
    }
    return first;
  }

  /// Jump to the next cue. A skipped own line is recorded as missed.
  void skip() {
    if (phase == Phase.finished) return;
    if (cues[position].mine) results.putIfAbsent(position, () => false);
    _next();
  }

  /// Step back one cue (or replay the first). Its first attempt stays.
  void back() {
    if (phase == Phase.finished) {
      if (cues.isEmpty) return;
      position = cues.length - 1;
    } else if (position > 0) {
      position--;
    }
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
