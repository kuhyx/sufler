import 'package:flutter/material.dart';
import 'package:sufler/ui/labels.dart';
import 'package:sufler/ui/option_segments.dart';
import 'package:sufler/ui/pc_session_tile.dart';
import 'package:sufler/ui/script_tabs.dart';
import 'package:sufler/ui/services.dart';
import 'package:sufler/ui/settings_card.dart';

/// The "Ustawienia próby" tab: tempo, text and learning modes, one group at a
/// time so it fits a phone screen.
class PracticeTab extends StatelessWidget {
  /// Creates the tab over [tabs]' state and callbacks.
  const new({required this.tabs, super.key});

  /// The hub's tabs.
  final ScriptTabs tabs;

  @override
  Widget build(BuildContext context) => OptionSegments(
    groups: [
      OptionGroup(
        icon: Icons.speed,
        label: groupTempoText,
        children: [
          SettingsCard(
            group: SettingsGroup.tempoText,
            speed: tabs.prefs.speed,
            settings: tabs.settings,
            onSpeed: tabs.onSpeed,
            onSettings: tabs.onSettings,
          ),
        ],
      ),
      OptionGroup(
        icon: Icons.school_outlined,
        label: groupModes,
        children: [
          SettingsCard(
            group: SettingsGroup.modes,
            speed: tabs.prefs.speed,
            settings: tabs.settings,
            onSpeed: tabs.onSpeed,
            onSettings: tabs.onSettings,
          ),
          if (ServicesScope.maybeOf(context) case Services(
            pcSession: final s?,
            :final relayKey,
          ))
            PcSessionTile(session: s, relayKey: relayKey),
        ],
      ),
    ],
  );
}
