import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/ui/pc_session_tile.dart';
import 'package:sufler/ui/script_tabs.dart';
import 'package:sufler/ui/services.dart';
import 'package:sufler/ui/settings_card.dart';

/// The "Ustawienia próby" tab: tempo, text and learning modes.
class PracticeTab extends StatelessWidget {
  /// Creates the tab over [tabs]' state and callbacks.
  const new({required this.tabs, super.key});

  /// The hub's tabs.
  final ScriptTabs tabs;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.md),
    children: [
      SettingsCard(
        speed: tabs.prefs.speed,
        settings: tabs.settings,
        onSpeed: tabs.onSpeed,
        onSettings: tabs.onSettings,
      ),
      if (ServicesScope.maybeOf(context)?.pcSession case final s?)
        PcSessionTile(session: s),
    ],
  );
}
