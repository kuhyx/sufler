import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sufler/import/pdf/pdf_reader.dart';
import 'package:sufler/import/readers/docx_reader.dart';
import 'package:sufler/import/readers/odt_reader.dart';
import 'package:sufler/import/readers/txt_reader.dart';
import 'package:sufler/import/structure/build_script.dart';
import 'package:sufler/model/script.dart';

export 'package:sufler/import/google_doc.dart'
    show GoogleDocException, googleDocId, importGoogleDoc;

/// Turns a dropped document into a [Script].
///
/// [fileName] picks the format by extension: .pdf, .docx, .odt, .txt.
/// Throws a [FormatException] for other extensions or unreadable files.
Future<Script> importDocument({
  required String fileName,
  required Uint8List bytes,
}) async {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  final read = switch (ext) {
    'pdf' => readPdf,
    'docx' => readDocx,
    'odt' => readOdt,
    'txt' => readTxt,
    _ => throw FormatException('Unsupported file type: $fileName'),
  };
  return buildScript(read(bytes), id: sha256Hex(bytes), source: fileName);
}

/// Hex SHA-256 of [bytes]: the [Script.id] of an imported document.
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();
