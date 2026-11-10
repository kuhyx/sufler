import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Text-free section header: a primary-tinted glyph on its own row; [spoken]
/// is the old heading, read aloud only (textgate).
class IconHeader extends StatelessWidget {
  /// Header glyph [icon] with screen-reader name [spoken].
  const new(this.icon, this.spoken, {super.key});

  /// The glyph.
  final IconData icon;

  /// The heading's spoken name.
  final String spoken;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Semantics(
      header: true,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
          semanticLabel: spoken,
        ),
      ),
    ),
  );
}
