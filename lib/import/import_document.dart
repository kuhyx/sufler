import 'dart:typed_data';

import 'package:sufler/model/script.dart';

/// Turns a dropped document into a [Script].
///
/// [fileName] picks the format by extension: .pdf, .docx, .odt, .txt.
/// Owned by the import layer; this stub is replaced by the real parser.
Future<Script> importDocument({
  required String fileName,
  required Uint8List bytes,
}) => throw UnimplementedError('importDocument');

/// Downloads a Google Docs share link (anyone with the link) as DOCX and
/// imports it.
Future<Script> importGoogleDoc(String url) =>
    throw UnimplementedError('importGoogleDoc');
