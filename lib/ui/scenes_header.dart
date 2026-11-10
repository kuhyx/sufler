import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/ui/learn_card.dart';
import 'package:sufler/ui/line_picker_screen.dart';
import 'package:sufler/ui/script_tabs.dart';

/// What goes above the scenes on "Sceny": the learn card and the ranges
/// that are not one scene (missed lines, custom, cumulative).
List<Widget> scenesHeader(ScriptTabs w) {
  final missed = w.prefs.missed.length;
  return [
    LearnCard(
      script: w.script,
      prefs: w.prefs,
      onResume: w.onResume,
      onStart: w.onStart,
      onRoles: w.onRoles,
    ),
    Wrap(
      spacing: AppSpacing.sm,
      children: [
        if (missed > 0)
          _RangeChip(
            leading: const Icon(Icons.replay),
            labelIcon: Icons.error_outline,
            semanticLabel: 'Tylko nieumiane ($missed)',
            onTap: w.onMissed,
          ),
        _RangeChip(
          leading: const Icon(Icons.straighten),
          labelIcon: Icons.crop_free,
          semanticLabel: 'Własny zakres…',
          onTap: () => w.onPick(PickMode.custom),
        ),
        _RangeChip(
          leading: const Icon(Icons.trending_up),
          labelIcon: Icons.stacked_line_chart,
          semanticLabel: 'Narastająco…',
          onTap: () => w.onPick(PickMode.cumulative),
        ),
      ],
    ),
  ];
}

/// A range shortcut: a chip with an icon, the [title] and the [subtitle]
/// as its tooltip.
class _RangeChip extends StatelessWidget {
  const new({
    required this.leading,
    required this.labelIcon,
    required this.semanticLabel,
    required this.onTap,
  });

  final Widget leading;
  final IconData labelIcon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: leading,
    label: Icon(labelIcon, semanticLabel: semanticLabel),
    onPressed: onTap,
  );
}
