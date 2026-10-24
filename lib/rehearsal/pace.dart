/// The actor's own speaking pace, learned from his recordings and tapped
/// times.
///
/// Seconds per syllable over every recorded line (speech only: a walk take
/// is trimmed to its speech span) and every line timed by a tap in "Nagraj
/// czasy" (line shown to "Skończyłem"), median so one slow or botched take
/// does not drag it. Computed on the fly, never stored.
library;

import 'package:sufler/model/script.dart';

/// Polish vowel letters.
const _vowels = 'aąeęioóuy';

/// Recorded lines needed before the pace is trusted.
const int minPaceSamples = 3;

/// Spoken syllables of [text]: one per Polish vowel letter, except an "i"
/// directly before another vowel, which only softens the consonant
/// ("się", "nie", "dzień" = 1; "ciocia" = 2). Diphthongs such as "au" are
/// not merged: rare, and pace and estimate use the same count anyway.
int spokenSyllables(String text) {
  final s = text.toLowerCase();
  var n = 0;
  for (var i = 0; i < s.length; i++) {
    if (!_vowels.contains(s[i])) continue;
    final glide = s[i] == 'i' && i + 1 < s.length && _vowels.contains(s[i + 1]);
    if (!glide) n++;
  }
  return n;
}

/// Median of non-empty [values].
double median(List<double> values) {
  final v = [...values]..sort();
  final mid = v.length ~/ 2;
  return v.length.isOdd ? v[mid] : (v[mid - 1] + v[mid]) / 2;
}

/// Median seconds per syllable over [recordingSeconds] (line index ->
/// speech length) and [tapSeconds] (line index -> tapped time) of
/// [script], or null below [minPaceSamples] usable samples (empty takes,
/// vowel-less lines and stale indices skipped). A line with both counts
/// once, by its recording.
double? secondsPerSyllable(
  Script script,
  Map<int, double> recordingSeconds, {
  Map<int, double> tapSeconds = const {},
}) {
  final rates = <double>[];
  final samples = {...tapSeconds, ...recordingSeconds};
  for (final MapEntry(key: i, value: s) in samples.entries) {
    if (s <= 0 || i < 0 || i >= script.lines.length) continue;
    final n = spokenSyllables(script.lines[i].text);
    if (n > 0) rates.add(s / n);
  }
  return rates.length < minPaceSamples ? null : median(rates);
}
