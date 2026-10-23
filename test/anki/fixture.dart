import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';

ScriptLine _line(
  int index,
  List<String> speakers,
  String text,
  LineKind kind,
  String sceneId, {
  String? songId,
}) => ScriptLine(
  index: index,
  speakers: speakers,
  text: text,
  kind: kind,
  sceneId: sceneId,
  songId: songId,
);

/// Synthetic play: two scenes, a song inside scene 2, a stage direction.
Script fixtureScript({String id = 'abc123'}) => Script(
  id: id,
  title: 'Sztuka',
  source: 'synthetic.pdf',
  characters: const [
    Character(id: 'anna', name: 'Anna'),
    Character(id: 'bartek', name: 'Bartek'),
  ],
  scenes: const [
    Section(id: 'scena-1', title: 'Scena 1', start: 0, end: 4),
    Section(id: 'scena-2', title: 'Scena 2', start: 5, end: 8),
  ],
  songs: const [Section(id: 'piosenka', title: 'Piosenka', start: 6, end: 7)],
  lines: [
    _line(0, [], 'Scena 1', LineKind.heading, 'scena-1'),
    _line(1, ['anna'], 'Dzień dobry.', LineKind.dialogue, 'scena-1'),
    _line(2, ['bartek'], 'Cześć, Anno.', LineKind.dialogue, 'scena-1'),
    _line(3, [], 'Wchodzi pies.', LineKind.direction, 'scena-1'),
    _line(4, ['anna'], 'Jak się masz?\nDobrze?', LineKind.dialogue, 'scena-1'),
    _line(5, ['anna'], 'Ja też.', LineKind.dialogue, 'scena-2'),
    _line(6, [], 'La la la', LineKind.song, 'scena-2', songId: 'piosenka'),
    _line(7, [], 'Tra la la', LineKind.song, 'scena-2', songId: 'piosenka'),
    _line(8, ['bartek', 'anna'], 'Koniec <b>.', LineKind.dialogue, 'scena-2'),
  ],
);

/// Anna plus the whole song: lines 1, 4, 5, 6, 7, 8 are hers.
final Set<Role> annaAndSong = {
  const Role.character('anna'),
  const Role.song('piosenka'),
};

/// Builds an audio pack zip holding clips for [indices] of [scriptId].
Uint8List packZip(String scriptId, List<int> indices) {
  final archive = Archive();
  final manifest = utf8.encode(
    jsonEncode({
      'scriptId': scriptId,
      'engine': 'fake@0',
      'voices': {'bartek': 'v1'},
      'lines': {for (final i in indices) '$i': 'audio/$i.ogg'},
    }),
  );
  archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
  for (final i in indices) {
    final clip = utf8.encode('OggS-clip-$i');
    archive.addFile(ArchiveFile('audio/$i.ogg', clip.length, clip));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// An [AudioPack] with clips for [indices].
AudioPack fixturePack(String scriptId, List<int> indices) =>
    AudioPack.fromZip(packZip(scriptId, indices));
