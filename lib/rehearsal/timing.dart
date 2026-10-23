/// How long the actor gets to say a line.
///
/// Precedence (highest first):
///   1. manual per-line override (absolute seconds, speed ignored),
///   2. own recording length + 1 s (absolute, speed ignored),
///   3. formula `syllables / 3.5 * 1.6 + 1.5`, divided by the speed.
library;

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

/// The pause for line [index] whose text is [text]; see the library doc.
double pauseSeconds({
  required int index,
  required String text,
  double speed = 1,
  Map<int, double> overrides = const {},
  Map<int, double> recordingSeconds = const {},
}) {
  final manual = overrides[index];
  if (manual != null) return manual;
  final recorded = recordingSeconds[index];
  if (recorded != null) return recorded + 1;
  return defaultPauseSeconds(text, speed: speed);
}
