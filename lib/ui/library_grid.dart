import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/ui/labels.dart';

/// Scripts as title-only tiles that always fit the screen: two columns on a
/// phone, four on a wide window, overflow paged sideways. Tap opens, hold
/// shows the details (source, line count, delete).
class LibraryGrid extends StatelessWidget {
  /// Creates the grid; [scripts] must not be empty.
  const new({
    required this.scripts,
    required this.onOpen,
    required this.onDelete,
    super.key,
  });

  /// The imported scripts.
  final List<Script> scripts;

  /// Called with a script's id when its tile is tapped.
  final ValueChanged<String> onOpen;

  /// Called when "Usuń" is pressed in a script's details sheet.
  final ValueChanged<Script> onDelete;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= wideLayout;
    return FitGrid(
      itemCount: scripts.length,
      columns: wide ? 4 : 2,
      minSquare: 0.4,
      itemBuilder: (context, i) {
        final s = scripts[i];
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onOpen(s.id),
            onLongPress: () => _showDetails(context, s),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(
                  s.title,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDetails(BuildContext context, Script s) =>
      showModalBottomSheet<void>(
        context: context,
        builder: (sheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.title, style: Theme.of(sheet).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${s.source} · ${s.lines.where((l) => l.isSpoken).length} '
                  'kwestii',
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Usuń'),
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    onDelete(s);
                  },
                ),
              ],
            ),
          ),
        ),
      );
}
