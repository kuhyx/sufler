// coverage:ignore-file
// Platform glue over file_picker / share_plus; needs real OS dialogs.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sufler/ui/services.dart';

/// Open via the system picker; save via the share sheet on Android and a
/// browser download on web.
class PlatformFiles implements FileAccess {
  @override
  Future<PickedFile?> pick(List<String> extensions) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (files.isEmpty) return null;
    final f = files.first;
    return (name: f.name, bytes: await f.readAsBytes());
  }

  @override
  Future<void> save(String fileName, Uint8List bytes, String mimeType) async {
    if (kIsWeb) {
      await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
      );
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: fileName, mimeType: mimeType)],
        fileNameOverrides: [fileName],
      ),
    );
  }
}
