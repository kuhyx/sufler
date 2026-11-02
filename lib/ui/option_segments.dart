import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/ui/option_tiles.dart';

/// Widest the option content grows, so tiles stay tile-sized on a desktop.
const double _maxContentWidth = 640;

/// One chip of an [OptionSegments] row and what it shows.
class OptionGroup {
  /// A group labelled [label] showing [child] while selected.
  const new({required this.label, required this.children});

  /// The chip text.
  final String label;

  /// The group's content, top to bottom; runs of tiles sit two to a row.
  final List<Widget> children;
}

/// A row of chips on top; only the selected [OptionGroup] shows below, so a
/// settings tab fits one screen. The selection is local UI state: it is lost
/// when the tab is rebuilt from scratch and never stored.
class OptionSegments extends StatefulWidget {
  /// Creates the chips and the selected group's content.
  const new({required this.groups, super.key});

  /// The groups, in chip order. The first one starts selected.
  final List<OptionGroup> groups;

  @override
  State<OptionSegments> createState() => _OptionSegmentsState();
}

class _OptionSegmentsState extends State<OptionSegments> {
  var _selected = 0;

  @override
  Widget build(BuildContext context) {
    final groups = widget.groups;
    final index = _selected.clamp(0, groups.length - 1);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxContentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final (i, g) in groups.indexed)
                    ChoiceChip(
                      label: Text(g.label),
                      selected: i == index,
                      onSelected: (_) => setState(() => _selected = i),
                    ),
                ],
              ),
            ),
            // Scrolls only as a safety net on a tiny window; the groups are
            // sized to fit a phone screen.
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                children: [OptionColumn(children: groups[index].children)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
