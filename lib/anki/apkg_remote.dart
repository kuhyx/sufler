/// Client half of `POST /api/apkg`: the web app hands a derived deck to the
/// desktop wrapper, which writes the `.apkg` with sqlite3.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sufler/anki/anki_deck.dart';

/// Wrapper route that turns an [AnkiDeck] JSON body into `.apkg` bytes.
const String apkgRoute = '/api/apkg';

/// The wrapper could not build the deck.
class ApkgExportException implements Exception {
  /// Creates the exception with a human-readable [message].
  const ApkgExportException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'ApkgExportException: $message';
}

/// Posts [deck] to the wrapper at [base] and returns the `.apkg` bytes.
///
/// Throws [ApkgExportException] on a non-200 answer, e.g. when the app is
/// opened as a plain web page with no wrapper behind it.
Future<Uint8List> postDeck(
  AnkiDeck deck, {
  required http.Client client,
  required Uri base,
}) async {
  final response = await client.post(
    base.resolve(apkgRoute),
    headers: {'content-type': 'application/json'},
    body: jsonEncode(deck.toJson()),
  );
  if (response.statusCode != 200) {
    throw ApkgExportException(
      'wrapper answered ${response.statusCode}: ${response.body}',
    );
  }
  return response.bodyBytes;
}
