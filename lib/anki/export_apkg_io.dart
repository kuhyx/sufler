import 'dart:typed_data';

import 'package:sufler/anki/apkg_writer.dart';
import 'package:sufler/anki/sufler_cards.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/line_note.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';

/// Builds an Anki `.apkg` for [roles] in [script]; see `sufler_cards.dart`
/// for which cards. Cue audio comes from [audio] when given, [notes] go on
/// the backs.
Future<Uint8List> exportApkg(
  Script script,
  Set<Role> roles, {
  AudioPack? audio,
  Map<int, List<LineNote>> notes = const {},
}) async => writeApkg(buildDeck(script, roles, audio: audio, notes: notes));
