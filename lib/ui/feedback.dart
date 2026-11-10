import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Text-free snack bars and the delete confirmation (textgate): an icon and
/// a colour on screen; the old sentence stays only as the spoken label.

/// A failure: error glyph on the danger hue; [spoken] is read aloud only.
void showFailure(BuildContext context, String spoken) => _snack(
  context,
  Icon(
    Icons.error_outline,
    color: context.statusColors.onStatus,
    semanticLabel: spoken,
  ),
  background: context.statusColors.danger,
  duration: const Duration(seconds: 5),
);

/// A success: check glyph on the neutral bar; [spoken] is read aloud only.
void showDone(BuildContext context, String spoken) => _snack(
  context,
  Icon(Icons.check_circle_outline, semanticLabel: spoken),
  duration: const Duration(seconds: 3),
);

void _snack(
  BuildContext context,
  Widget content, {
  required Duration duration,
  Color? background,
}) {
  // Null after the screen was popped mid-await: nothing to show then.
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Row(mainAxisSize: MainAxisSize.min, children: [content]),
        backgroundColor: background,
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

/// Asks before a delete: keep (focused, also Esc) or a red delete glyph.
Future<bool> confirmDelete(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      icon: const Icon(Icons.delete_forever_outlined),
      actions: [
        IconButton(
          key: const Key('confirm-cancel'),
          autofocus: true,
          onPressed: () => Navigator.of(dialog).pop(false),
          icon: const Icon(Icons.close, semanticLabel: 'Anuluj'),
        ),
        IconButton.filled(
          key: const Key('confirm-delete'),
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(dialog).colorScheme.error,
            foregroundColor: Theme.of(dialog).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(dialog).pop(true),
          icon: const Icon(Icons.delete_outline, semanticLabel: 'Usuń'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
