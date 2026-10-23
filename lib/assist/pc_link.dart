import 'dart:async';

import 'package:sufler/assist/assistant.dart';

/// The last known reachability of an [Assistant]'s PC, shared app-wide:
/// [Assistant.pcOnline] is listened to once per assistant, so any number
/// of screens and pending requests can wait for it.
class PcLink {
  /// The link of [assistant] (made on first use).
  factory of(Assistant assistant) => _links[assistant] ??= PcLink._(assistant);

  new _(this.assistant) {
    assistant.pcOnline.listen(_set, onError: (_) => _set(false));
  }

  static final _links = Expando<PcLink>();

  /// The PC side.
  final Assistant assistant;

  /// Last known state: null until the PC side said anything.
  bool? online;

  final _changes = StreamController<bool>.broadcast();

  /// Every reported change.
  Stream<bool> get changes => _changes.stream;

  void _set(bool on) {
    online = on;
    _changes.add(on);
  }

  /// A request failed: treat the PC as offline until it reports otherwise.
  void lost() => online = false;

  /// Completes once the PC is (reported) reachable.
  Future<void> get back =>
      online ?? false ? Future.value() : changes.firstWhere((on) => on);
}
