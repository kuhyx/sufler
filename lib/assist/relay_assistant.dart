/// The phone's assistant: requests to the PC through Firebase RTDB.
///
/// The phone cannot reach the PC's loopback service, so it PUTs
/// `sufler/requests/{rid}` `{kind, payload, deviceId, ts}` and polls
/// `sufler/results/{rid}` until the PC worker (`tts/sufler_tts/relay/`)
/// answers `{ok, text | audioB64 | error}`, then deletes the result
/// (DOCS-contract.md "Relay"). Polling, not a stream: one small GET a second
/// for a request in flight is cheaper than porting tutor's SSE client.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:sufler/assist/assist_error.dart';
import 'package:sufler/assist/assist_payload.dart';
import 'package:sufler/assist/assistant.dart';
import 'package:sufler/assist/pc_session.dart';
import 'package:sufler/assist/presence_poll.dart';
import 'package:sufler/assist/rtdb_client.dart';
import 'package:sufler/model/json.dart';
import 'package:sufler/model/script.dart';

/// RTDB root of everything sufler writes.
const relayRoot = 'sufler';

/// A presence beat older than this (server time) means the PC is gone.
const presenceStale = Duration(seconds: 75);

final Random _random = Random.secure();
const _alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/// A fresh 22-character url-safe request id (~131 random bits).
String newRequestId() => String.fromCharCodes([
  for (var i = 0; i < 22; i++)
    _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
]);

/// Explain and re-render through the PC, from anywhere with internet.
class RelayAssistant implements Assistant {
  /// Creates the assistant.
  new({
    required this.rtdb,
    required this.deviceId,
    required this.session,
    this.pollEvery = const Duration(seconds: 1),
    this.explainTimeout = const Duration(seconds: 150),
    this.renderTimeout = const Duration(seconds: 180),
    this.presenceEvery = const Duration(seconds: 20),
  });

  /// REST client rooted at the database URL.
  final RtdbClient rtdb;

  /// This install's persisted uuid (`device_id.dart`).
  final Future<String> Function() deviceId;

  /// The Firebase session; signed out means no relay.
  final PcSession session;

  /// How often a pending result is polled.
  final Duration pollEvery;

  /// Give up on an explanation after this long (Claude has 90 s on the PC).
  final Duration explainTimeout;

  /// Give up on a clip after this long (a cold engine loads the model).
  final Duration renderTimeout;

  /// How often [pcOnline] checks the PC's beat.
  final Duration presenceEvery;

  final StreamController<bool> _manual = StreamController.broadcast();

  Future<bool> _ensureSession() async =>
      await session.signedIn() || await session.signIn();

  /// Sends one request and waits for its result; null on timeout.
  Future<Json?> _ask(String kind, Json payload, Duration timeout) async {
    final rid = newRequestId();
    await rtdb.put('$relayRoot/requests/$rid', {
      'kind': kind,
      // A string: RTDB drops nulls and empty lists inside objects.
      'payload': jsonEncode(payload),
      'deviceId': await deviceId(),
      'ts': serverTime,
    });
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollEvery);
      final result = await rtdb.get('$relayRoot/results/$rid');
      if (result is Map<String, Object?>) {
        try {
          await rtdb.delete('$relayRoot/results/$rid');
        } on RtdbError {
          // The PC's GC removes it after 24 h.
        }
        return result;
      }
    }
    // Withdrawn, so a PC that comes back later spends nothing on it.
    try {
      await rtdb.delete('$relayRoot/requests/$rid');
    } on RtdbError {
      // The PC's 10-minute staleness rule drops it anyway.
    }
    return null;
  }

  @override
  Future<String> explain({
    required Script script,
    required int index,
    required String selection,
  }) async {
    if (!await _ensureSession()) {
      throw const AssistantError(
        'Zaloguj się (Ustawienia → Połącz z PC), żeby pytać PC z telefonu.',
      );
    }
    final Json? result;
    try {
      result = await _ask(
        'explain',
        explainPayload(script, index, selection),
        explainTimeout,
      );
    } on RtdbError catch (e) {
      throw AssistantError('Brak połączenia z bazą (${e.status ?? 'sieć'}).');
    }
    if (result == null) {
      throw const AssistantError('PC nie odpowiada — czy jest włączony?');
    }
    if (result case {'ok': true, 'text': final String text}) return text;
    throw AssistantError('PC nie wyjaśnił: ${result['error'] ?? 'błąd'}');
  }

  @override
  Future<Uint8List?> renderLine({
    required Script script,
    required int index,
  }) async {
    try {
      if (!await _ensureSession()) return null;
      final result = await _ask(
        'render_line',
        renderLinePayload(script, index),
        renderTimeout,
      );
      if (result case {'ok': true, 'audioB64': final String b64}) {
        return base64Decode(b64);
      }
    } on Object {
      // Network, auth or a malformed answer: no clip, the old one stays.
    }
    return null;
  }

  /// Whether the PC beat within [presenceStale], judged on server time:
  /// the phone PUTs a server timestamp and compares the beat with that.
  Future<bool> _probe() async {
    if (!await session.signedIn()) return false;
    final now = await rtdb.put(
      '$relayRoot/clients/${await deviceId()}/seen',
      serverTime,
    );
    final workers = await rtdb.get('$relayRoot/presence');
    if (now is! int || workers is! Map) return false;
    return workers.values.any(
      (w) =>
          w is Map &&
          w['beat'] is int &&
          now - (w['beat'] as int) < presenceStale.inMilliseconds,
    );
  }

  /// Checks presence now (tests; a UI "retry"), outside the timer.
  Future<void> checkPresenceNow() async {
    bool online;
    try {
      online = await _probe();
    } on Object {
      online = false;
    }
    _manual.add(online);
  }

  @override
  late final Stream<bool> pcOnline = _merge(
    pollPresence(_probe, presenceEvery),
  );

  /// The timer's answers plus [checkPresenceNow]'s, repeats dropped.
  Stream<bool> _merge(Stream<bool> polled) {
    bool? last;
    late StreamController<bool> out;
    final subs = <StreamSubscription<bool>>[];
    void emit({required bool online}) {
      if (online == last) return;
      last = online;
      out.add(online);
    }

    out = StreamController<bool>.broadcast(
      onListen: () {
        last = null;
        subs
          ..add(polled.listen((v) => emit(online: v)))
          ..add(_manual.stream.listen((v) => emit(online: v)));
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );
    return out.stream;
  }
}
