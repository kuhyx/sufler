import 'package:http/http.dart' as http;
import 'package:sufler/import/gdoc_endpoint.dart';
import 'package:sufler/import/import_document.dart';
import 'package:sufler/import/readers/docx_reader.dart';
import 'package:sufler/import/structure/build_script.dart';
import 'package:sufler/model/script.dart';

/// A Google Doc could not be fetched; [message] is shown to the user.
class GoogleDocException implements Exception {
  /// Creates the exception.
  const GoogleDocException(this.message);

  /// Human-readable reason.
  final String message;

  @override
  String toString() => 'GoogleDocException: $message';
}

final _docId = RegExp(
  r'docs\.google\.com/document/(?:u/\d+/)?d/([A-Za-z0-9_-]+)',
);

/// The document id in a `docs.google.com/document/d/<id>/...` link.
/// Throws a [FormatException] for any other URL.
String googleDocId(String url) {
  final m = _docId.firstMatch(url);
  if (m == null) throw FormatException('Not a Google Docs link: $url');
  return m[1]!;
}

/// Downloads a Google Docs share link (anyone with the link) as DOCX and
/// imports it. On the web the request goes through the local wrapper's
/// `/api/gdoc?id=` because Google sends no CORS headers.
Future<Script> importGoogleDoc(String url, {http.Client? client}) async {
  final id = googleDocId(url);
  final c = client ?? http.Client();
  final http.Response res;
  try {
    res = await c.get(gdocDownloadUri(id));
  } on Object catch (e) {
    throw GoogleDocException('Could not reach Google Docs: $e');
  } finally {
    if (client == null) c.close();
  }
  final bytes = res.bodyBytes;
  final isZip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4b;
  const private = [401, 403, 404];
  if (private.contains(res.statusCode) || (res.statusCode == 200 && !isZip)) {
    throw const GoogleDocException(
      'The document is not shared as "anyone with the link can view" '
      '(or does not exist). Change its sharing in Google Docs and retry.',
    );
  }
  if (res.statusCode != 200) {
    throw GoogleDocException('Download failed: HTTP ${res.statusCode}');
  }
  return buildScript(readDocx(bytes), id: sha256Hex(bytes), source: url);
}
