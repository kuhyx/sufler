import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/ui/labels.dart';

/// Step of the per-line pause buttons.
const double pauseStep = 0.5;

/// "Pauza 4,2 s" with − / + buttons; changes persist for that line.
class PauseControl extends StatelessWidget {
  /// Creates the control for a pause of [length].
  const new({
    required this.length,
    required this.onAdjust,
    this.estimated = false,
    super.key,
  });

  /// Current pause length of the line.
  final double length;

  /// The length is guessed from his pace: "szacowane" under it (its own
  /// line: beside the buttons it overflows a phone).
  final bool estimated;

  /// Called with −[pauseStep] or +[pauseStep].
  final ValueChanged<double> onAdjust;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _buttons(),
      if (estimated) const Icon(Icons.info_outline, semanticLabel: 'szacowane'),
    ],
  );

  Widget _buttons() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        icon: const Icon(Icons.remove, semanticLabel: 'Krótsza pauza'),
        onPressed: length > pauseStep ? () => onAdjust(-pauseStep) : null,
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Text(seconds(length), key: const Key('pause')),
      ),
      IconButton(
        icon: const Icon(Icons.add, semanticLabel: 'Dłuższa pauza'),
        onPressed: () => onAdjust(pauseStep),
      ),
    ],
  );
}
