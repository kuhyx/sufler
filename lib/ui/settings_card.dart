import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/rehearsal/timing.dart';
import 'package:sufler/storage/prefs.dart';

/// Speed, learning vs read-through, listening, self-grading and loop mode.
class SettingsCard extends StatelessWidget {
  /// Creates the card.
  const new({
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
        const SectionHeader('Tempo'),
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
        const SectionHeader('Tekst mojej kwestii'),
        const SizedBox(height: AppSpacing.xs),
        SegmentedButton<TextVisibility>(
          segments: const [
            ButtonSegment(
              value: TextVisibility.revealAfter,
              label: Text('Nauka'),
            ),
            ButtonSegment(
              value: TextVisibility.hide,
              label: Text('Bez tekstu'),
            ),
            ButtonSegment(value: TextVisibility.show, label: Text('Czytanie')),
          ],
          selected: {s.visibility},
          onSelectionChanged: (v) =>
              onSettings(s.copyWith(visibility: v.single)),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(switch (s.visibility) {
          TextVisibility.revealAfter =>
            'Mówisz z pamięci, potem widzisz tekst i oceniasz ✓/✗.',
          TextVisibility.hide => 'Tekstu nie widać nawet przy ocenie.',
          TextVisibility.show => 'Pierwsze czytanie: tekst widać od razu.',
        }, style: Theme.of(context).textTheme.bodySmall),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Oceniaj się ✓/✗'),
          value: s.grades,
          onChanged: s.grades && !s.selfGrade
              ? null
              : (v) => onSettings(s.copyWith(selfGrade: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Słuchaj mnie (mikrofon)'),
          subtitle: const Text(
            'kończy kwestię, gdy przestaniesz mówić, i podpowiada ocenę',
          ),
          value: s.listen,
          onChanged: (v) => onSettings(s.copyWith(listen: v)),
        ),
        SwitchListTile(
          key: const Key('whole-runs'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Piosenki i monologi w całości'),
          subtitle: const Text(
            'piosenkę lub ≥ 3 kwestie z rzędu mówisz naraz i oceniasz raz; '
            'cudze piosenki grają jako jeden krok',
          ),
          value: s.wholeRuns,
          onChanged: (v) => onSettings(s.copyWith(wholeRuns: v)),
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
