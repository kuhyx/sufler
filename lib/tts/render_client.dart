/// HTTP client for the voice service, reached through the desktop wrapper's
/// `/api/tts/*` proxy.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/json.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/tts/render_progress.dart';

/// Wrapper path prefix of the voice service.
const String ttsPrefix = '/api/tts';

/// INTEGRATION POINT with the voice service: `POST /render` is sent the bare
/// `Script.toJson()` (DOCS-contract.md "Script") as `application/json`, and
/// answers `{"jobId": "..."}`. `GET /jobs/<id>` answers
/// `{"done": n, "total": n, "state": "..."}`, where [jobDoneState] ends the
/// job and [jobFailedStates] fail it. `GET /packs/<scriptId>.zip` is the pack.
const String jobDoneState = 'done';

/// Job states that end the render with an error.
const Set<String> jobFailedStates = {'error', 'failed'};

/// Talks to `<base>/api/tts/...`.
class RenderClient {
  /// Creates a client; [base] is the app origin (`Uri.base` on web).
  new({
    required this.client,
    required this.base,
    this.pollInterval = const Duration(seconds: 1),
  });

  /// Transport.
  final http.Client client;

  /// App origin the wrapper serves.
  final Uri base;

  /// Delay between job polls.
  final Duration pollInterval;

  Uri _url(String path) => base.resolve('$ttsPrefix$path');

  /// Whether the voice service answers its health check.
  Future<bool> available() async {
    try {
      return (await client.get(_url('/health'))).statusCode == 200;
    } on Exception {
      return false;
    }
  }

  /// Renders [script]: one event per poll, then a final one with the pack.
  Stream<RenderProgress> render(Script script) async* {
    final started = await _json(
      client.post(
        _url('/render'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(script.toJson()),
      ),
    );
    final jobId = started['jobId']! as String;
    while (true) {
      final job = await _json(client.get(_url('/jobs/$jobId')));
      final done = job['done']! as int;
      final total = job['total']! as int;
      yield RenderProgress(done: done, total: total);
      final state = job['state'] as String?;
      if (jobFailedStates.contains(state)) {
        throw RenderException('render job $jobId ended in "$state"');
      }
      if (state == jobDoneState) {
        final pack = await client.get(_url('/packs/${script.id}.zip'));
        _check(pack);
        yield RenderProgress(
          done: done,
          total: total,
          pack: AudioPack.fromZip(pack.bodyBytes),
        );
        return;
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<Json> _json(Future<http.Response> request) async {
    final response = await request;
    _check(response);
    return jsonDecode(response.body) as Json;
  }

  void _check(http.Response response) {
    if (response.statusCode != 200) {
      throw RenderException(
        'voice service answered ${response.statusCode}: ${response.body}',
      );
    }
  }
}
