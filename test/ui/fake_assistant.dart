import 'dart:async';
import 'dart:typed_data';

import 'package:sufler/assist/assistant.dart';
import 'package:sufler/model/script.dart';

/// The PC side, faked: answers and renders at once while [online]; every
/// call fails while it is not. [pcOnline] says nothing until [setOnline].
class FakeAssistant implements Assistant {
  bool online = true;
  String answer = 'Powitanie; skojarzenie: wilk w lesie.';
  Uint8List? clip = Uint8List.fromList([7, 7]);
  final explained = <String>[];
  final rendered = <({int index, String text})>[];
  final _online = StreamController<bool>.broadcast();

  /// The PC comes up (or goes away), and says so.
  void setOnline({required bool on}) {
    online = on;
    _online.add(on);
  }

  @override
  Future<String> explain({
    required Script script,
    required int index,
    required String selection,
  }) async {
    explained.add(selection);
    if (!online) throw StateError('PC offline');
    return answer;
  }

  @override
  Future<Uint8List?> renderLine({
    required Script script,
    required int index,
  }) async {
    rendered.add((index: index, text: script.lines[index].text));
    if (!online) throw StateError('PC offline');
    return clip;
  }

  @override
  Stream<bool> get pcOnline => _online.stream;
}
