import 'dart:typed_data';

import 'package:sufler/model/script.dart';

/// Asks the PC: explain a selection, re-render one line's voice clip.
abstract class Assistant {
  /// Polish explanation of [selection] (meaning in context + 2-3 mnemonics).
  Future<String> explain({
    required Script script,
    required int index,
    required String selection,
  });

  /// The voice clip (ogg bytes, same format as pack clips) for line [index]
  /// of [script] as it is now; null when the PC cannot render it.
  Future<Uint8List?> renderLine({required Script script, required int index});

  /// Whether the PC side is reachable right now.
  Stream<bool> get pcOnline;
}
