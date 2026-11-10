import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// An outcome as a tinted glyph instead of a sentence (textgate): a green
/// check when [ok], else a red warning; [spoken] is read aloud only.
Widget statusGlyph(
  BuildContext context,
  String spoken, {
  required bool ok,
  Key? key,
}) {
  final colors = context.statusColors;
  return Align(
    key: key,
    alignment: AlignmentDirectional.centerStart,
    child: Icon(
      ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
      color: ok ? colors.success : colors.danger,
      semanticLabel: spoken,
    ),
  );
}
