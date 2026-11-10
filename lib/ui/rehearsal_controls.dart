import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/rehearsal/controller.dart';
import 'package:sufler/rehearsal/session.dart';

/// Bottom bar of a rehearsal: back, pause/resume, next.
class RehearsalControls extends StatelessWidget {
  /// Creates the bar for [controller].
  const new({required this.controller, super.key});

  /// The running rehearsal.
  final RehearsalController controller;

  @override
  Widget build(BuildContext context) {
    final ctl = controller;
    final over = ctl.session.phase == Phase.finished;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.skip_previous, semanticLabel: 'Wstecz'),
              onPressed: ctl.back,
            ),
            IconButton.filledTonal(
              icon: Icon(
                ctl.paused ? Icons.play_arrow : Icons.pause,
                semanticLabel: ctl.paused ? 'Wznów' : 'Pauza',
              ),
              onPressed: over ? null : (ctl.paused ? ctl.resume : ctl.pause),
            ),
            IconButton(
              icon: const Icon(Icons.skip_next, semanticLabel: 'Dalej'),
              onPressed: over ? null : ctl.skip,
            ),
          ],
        ),
      ),
    );
  }
}
