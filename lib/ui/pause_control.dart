import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/ui/labels.dart';

/// Step of the per-line pause buttons.
const double pauseStep = 0.5;

/// "Pauza 4,2 s" with − / + buttons; changes persist for that line.
class PauseControl extends StatelessWidget {
  /// Creates the control for a pause of [length].
  const new({required this.length, required this.onAdjust, super.key});

  /// Current pause length of the line.
  final double length;

  /// Called with −[pauseStep] or +[pauseStep].
  final ValueChanged<double> onAdjust;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        tooltip: 'Krótsza pauza',
        icon: const Icon(Icons.remove),
        onPressed: length > pauseStep ? () => onAdjust(-pauseStep) : null,
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Text('Pauza ${seconds(length)}', key: const Key('pause')),
      ),
      IconButton(
        tooltip: 'Dłuższa pauza',
        icon: const Icon(Icons.add),
        onPressed: () => onAdjust(pauseStep),
      ),
    ],
  );
}
