import 'dart:typed_data';

import 'package:sufler/assist/assistant.dart';
import 'package:sufler/model/script.dart';

/// No PC side: never online, every request fails. The default until a real
/// [Assistant] is wired in `main.dart`.
class OfflineAssistant implements Assistant {
  /// Creates the stand-in.
  const new();

  @override
  Future<String> explain({
    required Script script,
    required int index,
    required String selection,
  }) => Future.error(StateError('no PC assistant'));

  @override
  Future<Uint8List?> renderLine({
    required Script script,
    required int index,
  }) async => null;

  @override
  Stream<bool> get pcOnline => Stream.value(false);
}
