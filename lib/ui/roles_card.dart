import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/edits.dart';

/// Multi-select of the characters and songs the actor plays.
class RolesCard extends StatelessWidget {
  /// Creates the card.
  const new({
    required this.script,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  /// The script.
  final Script script;

  /// Currently picked roles.
  final Set<Role> selected;

  /// Called with the new selection.
  final ValueChanged<Set<Role>> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = roleOptions(script);
    Widget chips({required bool songs}) => Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final o in options.where((o) => o.role.isSong == songs))
          FilterChip(
            label: Text('${o.label} (${o.count})'),
            selected: selected.contains(o.role),
            onSelected: (on) => onChanged(
              on ? {...selected, o.role} : ({...selected}..remove(o.role)),
            ),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Twoje role'),
        const SizedBox(height: AppSpacing.sm),
        chips(songs: false),
        if (script.songs.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Piosenki', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          chips(songs: true),
        ],
      ],
    );
  }
}
