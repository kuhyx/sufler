/// "Is the PC there?" as a stream: probe on first listen, then every
/// [PresenceFeed.every], while anyone listens.
library;

import 'dart:async';

/// Shared presence polling for any number of listeners.
///
/// Every probe's answer is emitted, repeats included: `PcLink.back` waits
/// for the next `true` after a failed request, so an unchanged "online"
/// must still arrive. A new listener gets the last known answer at once.
/// A probe that throws counts as false.
class PresenceFeed {
  /// Creates the feed; nothing runs until someone listens.
  new(this.probe, this.every);

  /// One check of the PC.
  final Future<bool> Function() probe;

  /// Time between checks.
  final Duration every;

  final Set<MultiStreamController<bool>> _listeners = {};
  Timer? _timer;
  bool? _last;
  bool _running = false;

  /// The answers, starting with the last known one.
  Stream<bool> get stream => Stream.multi((c) {
    _listeners.add(c);
    if (_last case final last?) c.add(last);
    c.onCancel = () {
      _listeners.remove(c);
      if (_listeners.isEmpty) {
        _timer?.cancel();
        _timer = null;
      }
    };
    if (_timer == null) {
      _timer = Timer.periodic(every, (_) => unawaited(refresh()));
      unawaited(refresh());
    }
  });

  /// Probes now and tells every listener.
  Future<void> refresh() async {
    if (_running) return;
    _running = true;
    bool now;
    try {
      now = await probe();
    } on Object {
      now = false;
    }
    _running = false;
    _last = now;
    for (final c in _listeners.toList()) {
      c.add(now);
    }
  }
}
