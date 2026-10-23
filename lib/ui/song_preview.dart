import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/ui/labels.dart';

/// Lines shown before "Pokaż cały tekst".
const int previewLines = 3;

/// Spoken lyric lines of [song].
List<ScriptLine> songLyrics(Script s, Section song) => [
  for (var i = song.start; i <= song.end && i < s.lines.length; i++)
    if (s.lines[i].isSpoken && s.lines[i].songId == song.id) s.lines[i],
];

/// Who sings [song]: every distinct speaker, "Chór" for unattributed.
String songSingers(Script s, Section song) {
  final names = <String>[];
  for (final l in songLyrics(s, song)) {
    for (final n in speakerNames(s, l).split(', ')) {
      if (!names.contains(n)) names.add(n);
    }
  }
  return names.isEmpty ? '—' : names.join(', ');
}

/// What a song is before picking it: singers, line count, the first lyric
/// lines, and the whole text on demand.
class SongPreview extends StatefulWidget {
  /// Creates the preview of [song] in [script].
  const new({required this.script, required this.song, super.key});

  /// The script.
  final Script script;

  /// The song section.
  final Section song;

  @override
  State<SongPreview> createState() => _SongPreviewState();
}

class _SongPreviewState extends State<SongPreview> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final lyrics = songLyrics(widget.script, widget.song);
    final shown = _open ? lyrics : lyrics.take(previewLines).toList();
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Śpiewa: ${songSingers(widget.script, widget.song)} · '
          '${lyrics.length} wersów',
          style: small,
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final l in shown)
          Text(l.text, style: const TextStyle(fontStyle: FontStyle.italic)),
        if (lyrics.length > previewLines)
          TextButton(
            onPressed: () => setState(() => _open = !_open),
            child: Text(_open ? 'Zwiń' : 'Pokaż cały tekst'),
          ),
      ],
    );
  }
}
