import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/range.dart';
import 'package:sufler/ui/line_picker_screen.dart';

/// What to rehearse: a scene, a song, a custom range or a cumulative run.
class SectionsCard extends StatelessWidget {
  /// Creates the card.
  const new({
    required this.script,
    required this.onStart,
    required this.onPick,
    super.key,
  });

  /// The script.
  final Script script;

  /// Start rehearsing [range], titled with the label.
  final void Function(LineRange range, String label) onStart;

  /// Open the line picker in a mode.
  final ValueChanged<PickMode> onPick;

  Widget _tile(Section s, IconData icon) => ListTile(
    leading: Icon(icon),
    title: Text(s.title),
    subtitle: Text('kwestie ${s.start}–${s.end}'),
    trailing: const Icon(Icons.play_arrow),
    onTap: () => onStart(LineRange.section(s), s.title),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionHeader('Fragment'),
      ListTile(
        leading: const Icon(Icons.straighten),
        title: const Text('Własny zakres…'),
        subtitle: const Text('od kwestii do kwestii'),
        onTap: () => onPick(PickMode.custom),
      ),
      ListTile(
        leading: const Icon(Icons.trending_up),
        title: const Text('Narastająco…'),
        subtitle: const Text('od początku (lub sceny) do wybranej kwestii'),
        onTap: () => onPick(PickMode.cumulative),
      ),
      if (script.scenes.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        Text('Sceny', style: Theme.of(context).textTheme.labelLarge),
        for (final s in script.scenes) _tile(s, Icons.theaters),
      ],
      if (script.songs.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        Text('Piosenki', style: Theme.of(context).textTheme.labelLarge),
        for (final s in script.songs) _tile(s, Icons.music_note),
      ],
    ],
  );
}
