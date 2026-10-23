import 'dart:typed_data';

import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';

/// Builds an Anki `.apkg`: front = the cue before each of the actor's lines,
/// back = the actor's line. Cue audio comes from [audio] when given.
/// Owned by the Anki layer; this stub is replaced by the real writer.
Future<Uint8List> exportApkg(
  Script script,
  Set<Role> roles, {
  AudioPack? audio,
}) => throw UnimplementedError('exportApkg');
