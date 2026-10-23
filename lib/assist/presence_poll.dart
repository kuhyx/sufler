/// "Is the PC there?" as a stream: probe on listen, then every [every].
library;

import 'dart:async';

/// Emits [probe]'s answer when listened to and after every [every], only
/// when it changes; stops polling while nobody listens. A probe that throws
/// counts as false.
Stream<bool> pollPresence(Future<bool> Function() probe, Duration every) {
  late StreamController<bool> out;
  Timer? timer;
  bool? last;
  var running = false;

  Future<void> tick() async {
    if (running) return;
    running = true;
    bool now;
    try {
      now = await probe();
    } on Object {
      now = false;
    }
    running = false;
    if (out.hasListener && now != last) {
      last = now;
      out.add(now);
    }
  }

  out = StreamController<bool>.broadcast(
    onListen: () {
      last = null;
      unawaited(tick());
      timer = Timer.periodic(every, (_) => unawaited(tick()));
    },
    onCancel: () {
      timer?.cancel();
      timer = null;
    },
  );
  return out.stream;
}
