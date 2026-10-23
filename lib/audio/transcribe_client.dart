import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sufler/model/json.dart';

/// What the voice service heard in one clip; times in seconds from the
/// clip start, null when it found no speech.
typedef Transcript = ({String text, double? speechStart, double? speechEnd});

/// `POST /api/tts/transcribe?lang=pl` on the desktop wrapper, which the
/// voice service answers with `{"text", "segments", "speechStart",
/// "speechEnd", "engine"}` (DOCS-contract.md). Anything but a 200 (404: an
/// older service, 503: no recognizer loaded) or a network error means "no
/// transcript", never a failure: timing still works from the detector.
class TranscribeClient {
  /// Creates a client; [base] is the app origin (`Uri.base` on web).
  new({
    required this.client,
    required this.base,
    this.timeout = const Duration(seconds: 20),
  });

  /// Transport.
  final http.Client client;

  /// App origin the wrapper serves.
  final Uri base;

  /// Give up (no transcript) after this long.
  final Duration timeout;

  /// Transcribes Polish speech in [wav]; null when unavailable.
  Future<Transcript?> transcribe(Uint8List wav) async {
    try {
      final res = await client
          .post(
            base.resolve('/api/tts/transcribe?lang=pl'),
            headers: {'content-type': 'audio/wav'},
            body: wav,
          )
          .timeout(timeout);
      if (res.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Json;
      return (
        text: (json['text'] as String? ?? '').trim(),
        speechStart: (json['speechStart'] as num?)?.toDouble(),
        speechEnd: (json['speechEnd'] as num?)?.toDouble(),
      );
    } on Object {
      return null;
    }
  }
}
