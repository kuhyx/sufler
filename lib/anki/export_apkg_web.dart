import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sufler/anki/apkg_remote.dart';
import 'package:sufler/anki/sufler_cards.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/line_note.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';

/// Builds an Anki `.apkg` for [roles] in [script] via the desktop wrapper:
/// the deck is derived here, sqlite runs in the wrapper.
Future<Uint8List> exportApkg(
  Script script,
  Set<Role> roles, {
  AudioPack? audio,
  Map<int, List<LineNote>> notes = const {},
}) async {
  final client = http.Client();
  try {
    return await postDeck(
      buildDeck(script, roles, audio: audio, notes: notes),
      client: client,
      base: Uri.base,
    );
  } finally {
    client.close();
  }
}
