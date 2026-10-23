/// Why the PC could not answer an [explain] (shown to the actor as is).
///
/// `renderLine` never throws it: a clip it cannot get is just null.
library;

/// An explanation the PC could not give.
class AssistantError implements Exception {
  /// Creates the error.
  const new(this.message);

  /// Polish text for the actor (may carry the service's own reason).
  final String message;

  @override
  String toString() => 'AssistantError: $message';
}
