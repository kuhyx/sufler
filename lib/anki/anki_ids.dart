/// Stable Anki identities: note guids, checksums and numeric ids.
///
/// Ported from lyricanki (`lib/services/apkg/anki_ids.dart`), whose guid and
/// base91 output was diffed against genanki. Everything here is a pure
/// function of its input, so an export of the same script always produces the
/// same ids and a re-import updates notes instead of duplicating them.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Anki's own base91 alphabet (not standard base91, not base64), in Anki's
/// order. Verified against `genanki.util.BASE91_TABLE`.
const String base91Table =
    'abcdefghijklmnopqrstuvwxyz'
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    '0123456789'
    r'!#$%&()*+,-./:;<=>?@[]^_`{|}~';

/// Encodes [value] in Anki's base91, most-significant digit first. Zero
/// encodes to '' exactly as Anki and genanki do.
String encodeBase91(BigInt value) {
  final radix = BigInt.from(base91Table.length);
  final digits = <String>[];
  var remaining = value;
  while (remaining > BigInt.zero) {
    digits.add(base91Table[(remaining % radix).toInt()]);
    remaining = remaining ~/ radix;
  }
  return digits.reversed.join();
}

/// The Anki note guid for [key]: base91 of the first 8 bytes of SHA-256.
String guidFor(String key) {
  var value = BigInt.zero;
  for (final byte in sha256.convert(utf8.encode(key)).bytes.take(8)) {
    value = (value << 8) + BigInt.from(byte);
  }
  return encodeBase91(value);
}

/// `notes.csum` for a note's first field: the first 8 hex digits of SHA-1.
///
/// AnkiDroid uses it for duplicate detection, so it is written for real
/// rather than genanki's literal 0. Fields carry HTML; Anki strips tags before
/// hashing, so the tags are stripped here too.
int csumFor(String firstField) {
  final plain = firstField.replaceAll(RegExp('<[^>]*>'), '');
  final hex = sha1.convert(utf8.encode(plain)).toString().substring(0, 8);
  return int.parse(hex, radix: 16);
}

/// 2^51, written out: `1 << 51` is a 32-bit shift under dart2js.
const int _idFloor = 2251799813685248;

/// A positive numeric id derived from [key], in `[2^51, 2^51 + 2^48)`.
///
/// 48 hash bits plus a 2^51 floor: exact under dart2js (below 2^53, no
/// bitwise ops), and far above Anki's default deck `1` or any small id.
int stableId(String key) {
  var value = 0;
  for (final byte in sha256.convert(utf8.encode(key)).bytes.take(6)) {
    value = value * 256 + byte;
  }
  return _idFloor + value;
}
