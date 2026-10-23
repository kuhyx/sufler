import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/storage/prefs.dart';

/// The scene or song a rehearsal of [r] walks whole, so a pass with every
/// own line ✓ on the first try marks it; null for custom ranges and
/// "only lines I missed".
Section? pureRunSection(Script script, ResumePoint r) {
  if (r.missedOnly) return null;
  return [
    ...script.scenes,
    ...script.songs,
  ].where((s) => s.start == r.start && s.end == r.end).firstOrNull;
}

/// A section tile's title, with the "czysty przebieg" badge once [pure].
class SectionTitle extends StatelessWidget {
  /// Creates the title.
  const new({required this.section, required this.pure, super.key});

  /// The section.
  final Section section;

  /// Whether it had a pure run.
  final bool pure;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(child: Text(section.title)),
      if (pure) ...[
        const SizedBox(width: AppSpacing.sm),
        Tooltip(
          message: 'Czysty przebieg',
          child: Icon(
            Icons.verified,
            key: Key('pure-${section.id}'),
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    ],
  );
}
