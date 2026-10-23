import 'package:sufler/import/structure/directions.dart';
import 'package:sufler/import/structure/slug.dart';
import 'package:sufler/model/script.dart';

/// An open song: where lyrics go and who sings them.
class OpenSong {
  /// Opens a song.
  new(this.id, this.title, this.start, this.speakers);

  /// Section id.
  final String id;

  /// Title as written.
  final String title;

  /// Index of the heading line.
  final int start;

  /// Singers (the speaker block it sits in, or a heading inside it).
  List<String> speakers;

  /// Whether the lyrics are red: null until the first lyric line.
  bool? coloured;
}

/// Collects lines, scenes and songs while the structurer walks the source.
class ScriptSink {
  /// The lines so far; index == position.
  final List<ScriptLine> lines = [];

  /// Closed scenes.
  final List<Section> scenes = [];

  /// Closed songs.
  final List<Section> songs = [];
  final SlugRegistry _ids = SlugRegistry();
  String? _sceneId;
  late String _sceneTitle;
  int _sceneStart = 0;

  /// The song lyrics currently go to, if any.
  OpenSong? song;

  /// Appends a line in the current scene.
  void emit(
    LineKind kind,
    List<String> speakers,
    String text, {
    List<String> directions = const [],
    String? songId,
  }) => lines.add(
    ScriptLine(
      index: lines.length,
      speakers: List.unmodifiable(speakers),
      text: text,
      kind: kind,
      sceneId: _sceneId,
      songId: songId,
      directions: List.unmodifiable(directions),
    ),
  );

  /// Emits [text] as one line of [kind]; directions are split off and a
  /// line with nothing left becomes a direction.
  void emitText(
    LineKind kind,
    List<String> speakers,
    String text, {
    List<String> extraDirections = const [],
    String? songId,
  }) {
    final (clean, found) = splitDirections(text);
    final directions = [...extraDirections, ...found];
    if (clean.isEmpty && directions.isEmpty) return;
    emit(
      clean.isEmpty ? LineKind.direction : kind,
      speakers,
      clean,
      directions: directions,
      songId: songId,
    );
  }

  /// Closes the open scene and starts [title] with its heading line.
  void startScene(String title) {
    closeSong();
    _closeScene();
    _sceneId = _ids.take(title);
    _sceneTitle = title;
    _sceneStart = lines.length;
    emit(LineKind.heading, const [], title);
  }

  /// Starts a song section with its heading line.
  void startSong(String title, List<String> speakers) {
    closeSong();
    final s = OpenSong(_ids.take(title), title, lines.length, speakers);
    emit(LineKind.heading, const [], title, songId: s.id);
    song = s;
  }

  /// Ends the open song at its last line.
  void closeSong() {
    final s = song;
    if (s == null) return;
    song = null;
    var end = lines.length - 1;
    while (end > s.start && lines[end].songId != s.id) {
      end--;
    }
    songs.add(Section(id: s.id, title: s.title, start: s.start, end: end));
  }

  void _closeScene() {
    final id = _sceneId;
    if (id == null) return;
    final end = lines.length - 1;
    scenes.add(
      Section(id: id, title: _sceneTitle, start: _sceneStart, end: end),
    );
  }

  /// Closes everything still open.
  void finish() {
    closeSong();
    _closeScene();
    _sceneId = null;
  }
}
