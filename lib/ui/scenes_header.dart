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
    if (missed > 0)
      ListTile(
        leading: const Icon(Icons.replay),
        title: Text('Tylko nieumiane ($missed)'),
        subtitle: const Text('kwestie, przy których dałeś ✗'),
        onTap: w.onMissed,
      ),
    ListTile(
      leading: const Icon(Icons.straighten),
      title: const Text('Własny zakres…'),
      subtitle: const Text('od kwestii do kwestii'),
      onTap: () => w.onPick(PickMode.custom),
    ),
    ListTile(
      leading: const Icon(Icons.trending_up),
      title: const Text('Narastająco…'),
      subtitle: const Text('od początku (lub sceny) do wybranej kwestii'),
      onTap: () => w.onPick(PickMode.cumulative),
    ),
    const Divider(),
  ];
}
