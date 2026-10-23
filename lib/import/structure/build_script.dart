import 'package:sufler/import/structure/cast.dart';
import 'package:sufler/import/structure/headings.dart';
import 'package:sufler/import/structure/script_sink.dart';
import 'package:sufler/import/styled_line.dart';
import 'package:sufler/model/script.dart';

final _songWord = RegExp(r'^Piosenka\s*|["„”“]');
final _songIntro = RegExp('piosenk|śpiew', caseSensitive: false);

/// Turns the extracted lines of a play into a [Script] (DOCS-contract.md).
///
/// Speaker headings come from the cast list ("Bohaterowie:") plus short
/// capitalised lines that recur; typos and prefixes fold into aliases.
/// Text before the first scene or speaker heading (title page, cast,
/// colour legend) is not imported as lines.
Script buildScript(
  List<StyledLine> lines, {
  required String id,
  required String source,
}) {
  final texts = [for (final l in lines) l.text];
  final (castNames, castEnd) = castList(texts);
  final cast = Cast();
  for (final (i, name) in castNames.indexed) {
    if (cast.resolve(name, record: false)?.name != name) cast.add(name, i);
  }
  _infer(cast, lines, castEnd + 1);
  final last = lines.lastWhere(
    (l) => l.text.trim().isNotEmpty,
    orElse: () => const StyledLine(''),
  );
  final s = _Structurer(cast)..closing = isEndMarker(last.text) ? last : null;
  final from = s.firstStructural(texts, castEnd + 1);
  lines.skip(from < 0 ? castEnd + 1 : from).forEach(s.line);
  s.end();
  final fallback = source.replaceFirst(RegExp(r'\.[^./]*$'), '');
  return Script(
    id: id,
    title: findTitle(texts) ?? fallback,
    source: source,
    characters: [for (final m in cast.members) m.toCharacter()],
    scenes: s.out.scenes,
    songs: s.out.songs,
    lines: s.out.lines,
  );
}

/// Adds recurring heading-shaped lines (2+ times, each followed by text)
/// that the cast list does not already cover.
void _infer(Cast cast, List<StyledLine> lines, int from) {
  final counts = <String, int>{};
  final first = <String, int>{};
  for (var i = from; i < lines.length; i++) {
    if (lines[i].tint != Tint.normal) continue;
    final (name, _) = splitTrailingDirection(lines[i].text);
    if (!_headingShaped(name, 4)) continue;
    final next = lines.skip(i + 1).map((l) => l.text.trim());
    final text = next.firstWhere((t) => t.isNotEmpty, orElse: () => '');
    if (text.isEmpty || headingParts(text) != null) continue;
    counts[name] = (counts[name] ?? 0) + 1;
    first.putIfAbsent(name, () => i);
  }
  final recurring = counts.keys.where((k) => counts[k]! >= 2).toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  for (final name in recurring) {
    for (final part in headingParts(name)!) {
      if (cast.resolve(part) == null) cast.add(part, 1000 + first[name]!);
    }
  }
}

bool _headingShaped(String text, int maxWords) =>
    headingParts(text, maxWords: maxWords) != null &&
    !isSceneHeading(text) &&
    songTitle(text) == null;

class _Structurer {
  new(this.cast);

  final Cast cast;
  final ScriptSink out = ScriptSink();
  List<String> speakers = const [];
  final StringBuffer _text = StringBuffer();
  bool _wraps = false;
  List<String> _headDirections = [];
  Tint? _runTint;
  List<String>? _runSpeakers;

  /// The document's last line when it is an end-of-play marker ("Koniec").
  /// Only the last one: mid-play, "Koniec!" can be a character's line.
  StyledLine? closing;

  int firstStructural(List<String> texts, int from) {
    for (var i = from; i < texts.length; i++) {
      if (isSceneHeading(texts[i]) ||
          _heading(texts[i], record: false) != null) {
        return i;
      }
    }
    return -1;
  }

  /// Speaker ids and heading-line direction, when [text] is a heading.
  (List<String>, String?)? _heading(String text, {bool record = true}) {
    final (name, direction) = splitTrailingDirection(text);
    final parts = headingParts(name);
    if (parts == null || !_headingShaped(name, 8)) return null;
    final ids = <String>[];
    for (final p in parts) {
      final m = cast.resolve(p, record: false);
      if (m == null) return null;
      if (!ids.contains(m.id)) ids.add(m.id);
    }
    if (record) parts.forEach(cast.resolve);
    return (ids, direction);
  }

  /// Whether the pending text ends inside a `(` opened at most 4 lines ago
  /// (a direction running on); a stray `(` cannot swallow the play.
  bool get _insideParens {
    final t = '$_text';
    final open = t.lastIndexOf('(');
    if (open < 0 || t.indexOf(')', open) >= 0) return false;
    return '\n'.allMatches(t.substring(open)).length < 4;
  }

  void _flush() {
    out.emitText(
      LineKind.dialogue,
      speakers,
      '$_text',
      extraDirections: _headDirections,
    );
    _text.clear();
    _headDirections = [];
    _wraps = false;
  }

  void line(StyledLine l) {
    final text = l.text.trim();
    if (text.isEmpty) {
      _wraps = false;
      return;
    }
    final song = out.song;
    if (isSceneHeading(text)) {
      _flush();
      out.startScene(squash(text));
      speakers = const [];
      _runTint = null;
      return;
    }
    if (identical(l, closing)) {
      // Otherwise it reads as one more line of the last speaker.
      _flush();
      out
        ..closeSong()
        ..emit(LineKind.direction, const [], '', directions: [text]);
      speakers = const [];
      _runTint = null;
      return;
    }
    final title = songTitle(text);
    if (title != null) {
      _flush();
      // "Piosenka Macochy" is sung by Macocha, whoever spoke last.
      final named = cast.inflected(title.replaceAll(_songWord, ''));
      out.startSong(title, named == null ? speakers : [named.id]);
      return;
    }
    final heading = _insideParens ? null : _heading(text);
    if (heading != null) {
      if (song != null && song.coloured == true && l.tint == Tint.song) {
        song.speakers = heading.$1;
        return;
      }
      _flush();
      out.closeSong();
      speakers = heading.$1;
      _headDirections = [?heading.$2];
      _runTint = null;
      return;
    }
    if (song != null && _lyric(song, l, text)) return;
    if (l.tint != Tint.normal) return _coloured(l.tint, text);
    _runTint = null;
    if (_text.isNotEmpty) _text.write(_wraps ? ' ' : '\n');
    _text.write(text);
    _wraps = l.wraps;
  }

  /// Handles [text] as a lyric of [song]; false when the song has ended.
  bool _lyric(OpenSong song, StyledLine l, String text) {
    if (song.coloured == null && !text.startsWith('(')) {
      song.coloured = l.tint == Tint.song;
    }
    if (song.coloured == true && l.tint != Tint.song) {
      out.closeSong();
      return false;
    }
    out.emitText(LineKind.song, song.speakers, text, songId: song.id);
    return true;
  }

  /// Red or blue text outside a song section: one line per line. A red
  /// run that opens by announcing a song ("Róża i Lis śpiewają piosenkę")
  /// emits that line as a direction and takes its singers from it.
  void _coloured(Tint tint, String text) {
    _flush();
    if (_runTint != tint) {
      _runTint = tint;
      _runSpeakers = null;
      if (tint == Tint.song && _songIntro.hasMatch(text)) {
        final named = cast.mentionedIn(text);
        _runSpeakers = named.isEmpty ? speakers : named;
        out.emit(LineKind.direction, _runSpeakers!, '', directions: [text]);
        return;
      }
    }
    final singers = _runSpeakers ?? speakers;
    // An unheaded red passage becomes its own song section from its first
    // lyric on, so it can be picked as a song role; `line` then routes the
    // rest of the run through `_lyric`, which closes it on a colour change.
    if (tint == Tint.song && out.startUnheadedSong(text, singers)) {
      return out.emitText(LineKind.song, singers, text, songId: out.song!.id);
    }
    final kind = tint == Tint.song ? LineKind.song : LineKind.recitation;
    out.emitText(kind, singers, text);
  }

  void end() {
    _flush();
    out.finish();
  }
}
