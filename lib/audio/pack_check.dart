import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/script.dart';

/// Shown when a pack was rendered for a different parse of the text.
const String stalePackMessage =
    'Paczka głosów pochodzi z innej wersji tekstu — wygeneruj ponownie';

/// Shown for an old pack without a fingerprint that still fits the script.
const String unversionedPackMessage =
    'Paczka głosów bez znacznika wersji tekstu: jeśli głosy nie pasują do '
    'kwestii, wygeneruj ją ponownie';

/// Whether [pack] may be played for [script]: the pack to use (null:
/// ignore it) and a message for the user, if any.
///
/// A pack with a fingerprint must match [Script.fingerprint] (a partial
/// pack is fine). One without is accepted, with a warning, only when every
/// clip index is a line of the script.
({AudioPack? pack, String? message}) checkPack(Script script, AudioPack pack) {
  final print = pack.fingerprint;
  if (print != null) {
    return print == script.fingerprint
        ? (pack: pack, message: null)
        : (pack: null, message: stalePackMessage);
  }
  final last = script.lines.length - 1;
  if (pack.indices.any((i) => i < 0 || i > last)) {
    return (pack: null, message: stalePackMessage);
  }
  return (pack: pack, message: unversionedPackMessage);
}
