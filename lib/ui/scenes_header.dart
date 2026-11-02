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
            title: Text('Tylko nieumiane ($missed)'),
            subtitle: const Text('kwestie, przy których dałeś ✗'),
            onTap: w.onMissed,
          ),
        _RangeChip(
          leading: const Icon(Icons.straighten),
          title: const Text('Własny zakres…'),
          subtitle: const Text('od kwestii do kwestii'),
          onTap: () => w.onPick(PickMode.custom),
        ),
        _RangeChip(
          leading: const Icon(Icons.trending_up),
          title: const Text('Narastająco…'),
          subtitle: const Text('od początku (lub sceny) do wybranej kwestii'),
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
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Widget leading;
  final Text title;
  final Text subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: leading,
    label: title,
    tooltip: subtitle.data,
    onPressed: onTap,
  );
}
