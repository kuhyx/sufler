import 'package:flutter/foundation.dart';
import 'package:sufler/model/script.dart';

/// An inclusive run of line indices to rehearse.
@immutable
class LineRange {
  /// Lines [start]..[end], inclusive.
  const new(this.start, this.end);

  /// A whole scene or song.
  factory section(Section s) => LineRange(s.start, s.end);

  /// A custom from-to pick; the order of the two taps does not matter.
  factory custom(int a, int b) => a <= b ? LineRange(a, b) : LineRange(b, a);

  /// Everything from [from] (the play's start, or a section start) up to and
  /// including [upTo]: the "add one more line each time" drill.
  const new cumulative({required int upTo, int from = 0}) : this(from, upTo);

  /// First line index.
  final int start;

  /// Last line index (inclusive).
  final int end;

  @override
  bool operator ==(Object other) =>
      other is LineRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'LineRange($start..$end)';
}
