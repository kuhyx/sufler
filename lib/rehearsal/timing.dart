/// How long the actor gets to say a line.
///
/// Precedence (highest first):
///   1. manual per-line override (absolute seconds, speed ignored),
///   2. own recording length + 1 s (absolute, speed ignored),
///   3. estimate from his own pace (`pace.dart`): median seconds per
///      syllable x the line's spoken syllables + 1 s, as if he had recorded
///      it (absolute, speed ignored; only with >= 3 recorded or tapped
///      lines),
///   4. formula `syllables / 3.5 * 1.6 + 1.5`, divided by the speed.
library;

import 'package:sufler/rehearsal/pace.dart';

/// Polish vowel letters; each one counts as a syllable nucleus.
const _vowels = 'aąeęioóuy';

/// Slowest and fastest allowed global speed multipliers.
const double minSpeed = 0.5;

/// See [minSpeed].
const double maxSpeed = 3;

/// Counts Polish vowel letters in [text]. Digraphs such as `ie` count twice
/// on purpose: the estimate should err long, never cut the actor off.
int syllableCount(String text) {
  var n = 0;
  for (final ch in text.toLowerCase().split('')) {
    if (_vowels.contains(ch)) n++;
  }
  return n;
}

/// Formula pause for [text] at the given global [speed].
double defaultPauseSeconds(String text, {double speed = 1}) {
  final s = speed.clamp(minSpeed, maxSpeed);
  return (syllableCount(text) / 3.5 * 1.6 + 1.5) / s;
}

/// Where a line's pause comes from (see the library doc).
enum PauseSource {
  /// A per-line manual value.
  manual,

  /// The actor's own recording of the line.
  recording,

  /// Guessed from his pace over the recorded and tapped lines.
  estimate,

  /// The syllable formula.
  formula,
}

/// The pause for line [index] whose text is [text] and its source; [pace]
/// is [secondsPerSyllable] (null: no estimate).
({double seconds, PauseSource source}) resolvePause({
  required int index,
  required String text,
  double speed = 1,
  Map<int, double> overrides = const {},
  Map<int, double> recordingSeconds = const {},
  double? pace,
}) {
  final manual = overrides[index];
  if (manual != null) return (seconds: manual, source: PauseSource.manual);
  final recorded = recordingSeconds[index];
  if (recorded != null) {
    return (seconds: recorded + 1, source: PauseSource.recording);
  }
  final n = spokenSyllables(text);
  if (pace != null && n > 0) {
    return (seconds: pace * n + 1, source: PauseSource.estimate);
  }
  return (
    seconds: defaultPauseSeconds(text, speed: speed),
    source: PauseSource.formula,
  );
}

/// The pause length alone; see [resolvePause].
double pauseSeconds({
  required int index,
  required String text,
  double speed = 1,
  Map<int, double> overrides = const {},
  Map<int, double> recordingSeconds = const {},
  double? pace,
}) => resolvePause(
  index: index,
  text: text,
  speed: speed,
  overrides: overrides,
  recordingSeconds: recordingSeconds,
  pace: pace,
).seconds;
