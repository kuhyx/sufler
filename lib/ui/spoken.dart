import 'package:flutter/widgets.dart';

/// Gives [child] (glyphs and numbers) one spoken label, [semanticLabel],
/// and hides its own nodes from the screen reader. Nothing here is painted:
/// the words exist for TalkBack and tests only (textgate R7).
class Spoken extends StatelessWidget {
  /// [child] read aloud as [semanticLabel].
  const new({required this.semanticLabel, required this.child, super.key});

  /// What the screen reader says.
  final String semanticLabel;

  /// What is painted.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Semantics(label: semanticLabel, excludeSemantics: true, child: child);
}
