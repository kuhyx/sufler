import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/rehearsal/timing.dart';
import 'package:sufler/storage/prefs.dart';

/// Speed, own-line visibility, self-grading and loop mode.
class SettingsCard extends StatelessWidget {
  /// Creates the card.
  const SettingsCard({
    required this.speed,
    required this.settings,
    required this.onSpeed,
    required this.onSettings,
    super.key,
  });

  /// Global speed multiplier (per script).
  final double speed;

  /// App-wide rehearsal settings.
  final AppSettings settings;

  /// New speed.
  final ValueChanged<double> onSpeed;

  /// New settings.
  final ValueChanged<AppSettings> onSettings;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Ustawienia próby'),
        const SizedBox(height: AppSpacing.sm),
        Text('Tempo ${speed.toStringAsFixed(2)}×'),
        Slider(
          value: speed,
          min: minSpeed,
          max: maxSpeed,
          divisions: 10,
          label: '${speed.toStringAsFixed(2)}×',
          onChanged: onSpeed,
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text('Tekst mojej kwestii'),
        const SizedBox(height: AppSpacing.xs),
        SegmentedButton<TextVisibility>(
          segments: const [
            ButtonSegment(value: TextVisibility.show, label: Text('Pokaż')),
            ButtonSegment(value: TextVisibility.hide, label: Text('Ukryj')),
            ButtonSegment(
              value: TextVisibility.revealAfter,
              label: Text('Po pauzie'),
            ),
          ],
          selected: {s.visibility},
          onSelectionChanged: (v) =>
              onSettings(s.copyWith(visibility: v.single)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Oceniaj się ✓/✗'),
          value: s.selfGrade || s.loop,
          onChanged: s.loop
              ? null
              : (v) => onSettings(s.copyWith(selfGrade: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Powtarzaj do skutku'),
          subtitle: const Text('aż do N czystych przebiegów z rzędu'),
          value: s.loop,
          onChanged: (v) => onSettings(s.copyWith(loop: v)),
        ),
        Row(
          children: [
            Expanded(child: Text('Czyste przebiegi: ${s.cleanTarget}')),
            IconButton(
              tooltip: 'Mniej przebiegów',
              icon: const Icon(Icons.remove),
              onPressed: s.cleanTarget > 1
                  ? () => onSettings(s.copyWith(cleanTarget: s.cleanTarget - 1))
                  : null,
            ),
            IconButton(
              tooltip: 'Więcej przebiegów',
              icon: const Icon(Icons.add),
              onPressed: () =>
                  onSettings(s.copyWith(cleanTarget: s.cleanTarget + 1)),
            ),
          ],
        ),
      ],
    );
  }
}
