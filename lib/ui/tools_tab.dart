import 'package:flutter/material.dart';
import 'package:sufler/ui/script_tabs.dart';
import 'package:sufler/ui/tools_card.dart';

/// The "Narzędzia" tab: parse, corrections, timings, Anki, voices.
class ToolsTab extends StatelessWidget {
  /// Creates the tab over [tabs]' state and callbacks.
  const new({required this.tabs, super.key});

  /// The hub's tabs.
  final ScriptTabs tabs;

  @override
  Widget build(BuildContext context) => ToolsCard(
    script: tabs.script,
    roles: tabs.prefs.roles,
    notes: tabs.prefs.notes,
    pack: tabs.pack,
    canRender: tabs.canRender,
    onPack: tabs.onPack,
    onCorrect: tabs.onCorrect,
    onTimings: tabs.onTimings,
    onRefreshParse: tabs.onRefreshParse,
  );
}
