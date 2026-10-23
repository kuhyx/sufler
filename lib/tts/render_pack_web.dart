import 'package:http/http.dart' as http;
import 'package:sufler/model/script.dart';
import 'package:sufler/tts/render_client.dart';
import 'package:sufler/tts/render_progress.dart';

RenderClient _client() => RenderClient(client: http.Client(), base: Uri.base);

/// Whether the wrapper and the voice service behind it are both up.
Future<bool> renderAvailable() async {
  final client = _client();
  try {
    return await client.available();
  } finally {
    client.client.close();
  }
}

/// Renders (or fetches the cached) audio pack for [script].
Stream<RenderProgress> renderPack(Script script) async* {
  final client = _client();
  try {
    yield* client.render(script);
  } finally {
    client.client.close();
  }
}
