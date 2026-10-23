import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/labels.dart';
import 'package:sufler/ui/learn_card.dart';
import 'package:sufler/ui/line_picker_screen.dart';
import 'package:sufler/ui/pc_session_tile.dart';
import 'package:sufler/ui/sections_tab.dart';
import 'package:sufler/ui/services.dart';
import 'package:sufler/ui/settings_card.dart';
import 'package:sufler/ui/tools_card.dart';

/// The script hub's tabs: "Sceny", "Piosenki", "Ustawienia próby",
/// "Narzędzia". A bottom navigation bar on a phone, a side rail on a wide
/// desktop window.
class ScriptTabs extends StatefulWidget {
  /// Creates the tabs; every action is the screen's.
  const new({
    required this.script,
    required this.prefs,
    required this.settings,
    required this.pack,
    required this.canRender,
    required this.onRoles,
    required this.onStart,
    required this.onMissed,
    required this.onResume,
    required this.onRecord,
    required this.onPick,
    required this.onSpeed,
    required this.onSettings,
    required this.onPack,
    required this.onCorrect,
    required this.onTimings,
    this.onRefreshParse,
    super.key,
  });

  /// The script.
  final Script script;

  /// Per-script prefs.
  final RehearsalPrefs prefs;

  /// App-wide settings.
  final AppSettings settings;

  /// Loaded voice pack.
  final AudioPack? pack;

  /// Whether voices can be generated.
  final bool canRender;

  /// Open "Moje role".
  final VoidCallback onRoles;

  /// Rehearse a range.
  final RangeAction onStart;

  /// Rehearse only the lines I missed.
  final VoidCallback onMissed;

  /// Continue the last rehearsal.
  final ValueChanged<ResumePoint> onResume;

  /// Record my timings over a range.
  final RangeAction onRecord;

  /// Open the line picker.
  final ValueChanged<PickMode> onPick;

  /// New speed.
  final ValueChanged<double> onSpeed;

  /// New settings.
  final ValueChanged<AppSettings> onSettings;

  /// A pack was stored.
  final ValueChanged<AudioPack> onPack;

  /// Open corrections.
  final VoidCallback onCorrect;

  /// Open timings.
  final VoidCallback onTimings;

  /// Pick the document to refresh an old parse; null: nothing to refresh.
  final VoidCallback? onRefreshParse;

  @override
  State<ScriptTabs> createState() => _ScriptTabsState();
}

const List<({String label, IconData icon})> _tabs = [
  (label: 'Sceny', icon: Icons.theaters),
  (label: 'Piosenki', icon: Icons.music_note),
  (label: 'Ustawienia próby', icon: Icons.tune),
  (label: 'Narzędzia', icon: Icons.build_outlined),
];

class _ScriptTabsState extends State<ScriptTabs> {
  int _tab = 0;

  List<Widget> get _scenesHeader {
    final w = widget;
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

  Widget _page(int tab) {
    final w = widget;
    Widget list(Widget child) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kProseMaxWidth),
        child: child,
      ),
    );
    return list(switch (tab) {
      0 => SectionsTab(
        script: w.script,
        sections: w.script.scenes,
        icon: Icons.theaters,
        prefs: w.prefs,
        onStart: w.onStart,
        onRecord: w.onRecord,
        header: _scenesHeader,
      ),
      1 => SectionsTab(
        script: w.script,
        sections: w.script.songs,
        icon: Icons.music_note,
        prefs: w.prefs,
        onStart: w.onStart,
        onRecord: w.onRecord,
        songs: true,
      ),
      2 => ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          SettingsCard(
            speed: w.prefs.speed,
            settings: w.settings,
            onSpeed: w.onSpeed,
            onSettings: w.onSettings,
          ),
          if (ServicesScope.maybeOf(context)?.pcSession case final s?)
            PcSessionTile(session: s),
        ],
      ),
      _ => ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          ToolsCard(
            script: w.script,
            roles: w.prefs.roles,
            pack: w.pack,
            canRender: w.canRender,
            onPack: w.onPack,
            onCorrect: w.onCorrect,
            onTimings: w.onTimings,
            onRefreshParse: w.onRefreshParse,
          ),
        ],
      ),
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= wideLayout;
    final appBar = AppBar(
      title: Text(widget.script.title),
      actions: [
        TextButton.icon(
          onPressed: widget.onRoles,
          icon: const Icon(Icons.person_outline),
          label: const Text('Moje role'),
        ),
      ],
    );
    void go(int i) => setState(() => _tab = i);
    if (!wide) {
      return Scaffold(
        appBar: appBar,
        body: _page(_tab),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: go,
          destinations: [
            for (final t in _tabs)
              NavigationDestination(icon: Icon(t.icon), label: t.label),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: appBar,
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _tab,
            onDestinationSelected: go,
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final t in _tabs)
                NavigationRailDestination(
                  icon: Icon(t.icon),
                  label: Text(t.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _page(_tab)),
        ],
      ),
    );
  }
}
