import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

const double _tileHeight = 88;
const double _iconRowHeight = 24;

/// Marks the tiles an [OptionColumn] sets two to a row.
abstract interface class OptionTile implements Widget;

/// A full-width column in which runs of consecutive [OptionTile]s sit two to
/// a row, the row as tall as its tallest tile; any other child (a slider, a
/// stepper, a progress bar) takes the whole row.
class OptionColumn extends StatelessWidget {
  /// Creates the column.
  const new({required this.children, super.key});

  /// The children, top to bottom.
  final List<Widget> children;

  Widget _row(Widget a, Widget? b) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: a),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: b ?? const SizedBox.shrink()),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      final c = children[i];
      if (c is OptionTile) {
        final next = i + 1 < children.length ? children[i + 1] : null;
        final pair = next is OptionTile ? next : null;
        rows.add(_row(c, pair));
        if (pair != null) i++;
      } else {
        rows.add(c);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, r) in rows.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          r,
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const new({
    required this.title,
    required this.body,
    required this.onTap,
    required this.info,
    this.leading,
  });

  final Widget title;
  final Widget body;
  final VoidCallback? onTap;
  final String? info;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      // The surface is nearly the page colour and the shadow falls below, so
      // an outline is what makes the top edge visible.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      // The explanation is spoken only (textgate): a hint, never painted.
      child: Semantics(
        hint: info,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _tileHeight),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fixed height, so titles line up across a row even when only
                  // one tile has an icon.
                  SizedBox(
                    height: _iconRowHeight,
                    child: Row(children: [?leading]),
                  ),
                  DefaultTextStyle.merge(
                    style: theme.textTheme.bodyLarge,
                    child: title,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  body,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A square-ish tile for an on/off option: the title and its switch. A
/// long press explains it ([info]); a null [onChanged] disables it.
class ToggleTile extends StatelessWidget implements OptionTile {
  /// Creates the tile.
  const new({
    required this.title,
    required this.value,
    required this.onChanged,
    this.info,
    super.key,
  });

  /// What the option is.
  final Widget title;

  /// Whether it is on.
  final bool value;

  /// New value; null disables the tile.
  final ValueChanged<bool>? onChanged;

  /// Longer explanation, spoken only (screen-reader hint).
  final String? info;

  @override
  Widget build(BuildContext context) => _Tile(
    title: title,
    info: info,
    onTap: onChanged == null ? null : () => onChanged!(!value),
    body: Switch(value: value, onChanged: onChanged),
  );
}

/// A tile that runs one action when tapped; [info] opens on long press.
class ActionTile extends StatelessWidget implements OptionTile {
  /// Creates the tile.
  const new({
    required this.icon,
    required this.title,
    required this.onTap,
    this.info,
    super.key,
  });

  /// Leading icon.
  final IconData icon;

  /// The action's name.
  final Widget title;

  /// Runs the action; null disables the tile.
  final VoidCallback? onTap;

  /// Longer explanation, spoken only (screen-reader hint).
  final String? info;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final theme = Theme.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: _Tile(
        title: title,
        info: info,
        onTap: onTap,
        leading: Icon(icon, color: theme.colorScheme.primary),
        body: const SizedBox.shrink(),
      ),
    );
  }
}
