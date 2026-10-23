/// The desktop (web) assistant: the wrapper's `/api/tts/*` proxy straight
/// to the voice service on this PC (DOCS-contract.md "Assistant").
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sufler/assist/assist_error.dart';
import 'package:sufler/assist/assist_payload.dart';
import 'package:sufler/assist/assistant.dart';
import 'package:sufler/assist/presence_poll.dart';
import 'package:sufler/model/script.dart';

/// Text shown when the voice service does not answer at all.
const serviceDown = 'Usługa na PC nie działa (sufler-tts).';

/// `POST /api/tts/explain` and `/api/tts/render_line`; online = `/health`.
class HttpAssistant implements Assistant {
  /// Creates the assistant; [base] is the app origin (`Uri.base` on web).
  new({
    required this.client,
    required this.base,
    this.healthEvery = const Duration(seconds: 30),
    this.explainTimeout = const Duration(seconds: 120),
    this.renderTimeout = const Duration(seconds: 120),
  });

  /// Transport.
  final http.Client client;

  /// App origin the wrapper serves.
  final Uri base;

  /// How often [pcOnline] asks `/health`.
  final Duration healthEvery;

  /// Claude gets 90 s on the PC; this covers it plus the round trip.
  final Duration explainTimeout;

  /// One line through the engine (cold start loads the model).
  final Duration renderTimeout;

  Future<http.Response> _post(String path, Object body, Duration timeout) =>
      client
          .post(
            base.resolve('/api/tts/$path'),
            headers: {'content-type': 'application/json; charset=utf-8'},
            body: jsonEncode(body),
          )
          .timeout(timeout);

  @override
  Future<String> explain({
    required Script script,
    required int index,
    required String selection,
  }) async {
    final http.Response res;
    try {
      res = await _post(
        'explain',
        explainPayload(script, index, selection),
        explainTimeout,
      );
    } on Object {
      throw const AssistantError(serviceDown);
    }
    Object? body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      body = null;
    }
    if (body case {'text': final String text} when res.statusCode == 200) {
      return text;
    }
    final reason = body is Map ? body['error'] : null;
    throw AssistantError(
      'PC nie wyjaśnił: ${reason ?? 'HTTP ${res.statusCode}'}',
    );
  }

  @override
  Future<Uint8List?> renderLine({
    required Script script,
    required int index,
  }) async {
    try {
      final res = await _post(
        'render_line',
        renderLinePayload(script, index),
        renderTimeout,
      );
      return res.statusCode == 200 ? res.bodyBytes : null;
    } on Object {
      return null;
    }
  }

  @override
  Stream<bool> get pcOnline => _presence.stream;

  late final PresenceFeed _presence = PresenceFeed(() async {
    final res = await client
        .get(base.resolve('/api/tts/health'))
        .timeout(const Duration(seconds: 5));
    return res.statusCode == 200;
  }, healthEvery);
}
