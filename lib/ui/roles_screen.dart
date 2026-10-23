import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/edits.dart';
import 'package:sufler/rehearsal/groups.dart';
import 'package:sufler/ui/services.dart';
import 'package:sufler/ui/song_preview.dart';

/// "Moje role": the characters, group speakers and songs the actor plays.
/// Every change is saved at once. Ticking a character also ticks the groups
/// it belongs to (untick to drop them).
class RolesScreen extends StatefulWidget {
  /// Opens the roles of stored script [scriptId].
  const new({required this.scriptId, super.key});

  /// Id of the script in the library.
  final String scriptId;

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  Script? _script;
  Set<Role> _roles = const {};
  List<GroupOption> _groups = const [];

  Services get _svc => ServicesScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_script == null) unawaited(_load());
  }

  Future<void> _load() async {
    final script = await _svc.library.loadScript(widget.scriptId);
    final prefs = await _svc.library.loadPrefs(widget.scriptId);
    if (!mounted || script == null) return;
    setState(() {
      _script = script;
      _roles = prefs.roles;
      _groups = groupOptions(script);
    });
  }

  Future<void> _set(Set<Role> roles) async {
    setState(() => _roles = roles);
    await _svc.library.updatePrefs(
      widget.scriptId,
      (p) => p.copyWith(roles: roles),
    );
  }

  void _toggle(Role role, {required bool on}) {
    if (!on) {
      unawaited(_set({..._roles}..remove(role)));
      return;
    }
    final more = role.kind == RoleKind.character
        ? suggestedGroups(_groups, {role.id})
        : const <Role>{};
    unawaited(_set({..._roles, role, ...more}));
  }

  Set<String> get _characters => {
    for (final r in _roles)
      if (r.kind == RoleKind.character) r.id,
  };

  @override
  Widget build(BuildContext context) {
    final s = _script;
    return Scaffold(
      appBar: AppBar(title: const Text('Moje role')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kProseMaxWidth),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: _content(s),
                ),
              ),
            ),
    );
  }

  List<Widget> _content(Script s) {
    final ensembles = {for (final g in _groups) g.role};
    final people = roleOptions(s)
        .where((o) => !o.role.isSong && !ensembles.contains(o.role));
    final suggested = suggestedGroups(_groups, _characters);
    return [
      const SectionHeader('Twoje role'),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final o in people)
            FilterChip(
              label: Text('${o.label} (${o.count})'),
              selected: _roles.contains(o.role),
              onSelected: (on) => _toggle(o.role, on: on),
            ),
        ],
      ),
      if (_groups.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader('Grupy'),
        for (final g in _groups) _group(s, g, suggested: suggested),
      ],
      if (s.songs.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader('Piosenki'),
        for (final song in s.songs) _song(s, song),
      ],
      const SizedBox(height: AppSpacing.lg),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Gotowe'),
      ),
    ];
  }

  Widget _group(Script s, GroupOption g, {required Set<Role> suggested}) {
    final extra = extraLines(s, g.role, _roles);
    final notes = [
      if (suggested.contains(g.role)) 'twoja grupa',
      if (extra == 0) 'te kwestie już masz' else '+$extra dla Ciebie',
    ];
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${g.label} (${g.count})'),
      subtitle: Text(notes.join(' · ')),
      value: _roles.contains(g.role),
      onChanged: (on) => _toggle(g.role, on: on ?? false),
    );
  }

  Widget _song(Script s, Section song) {
    final role = Role.song(song.id);
    final count = s.lines.where((l) => isMine(l, {role})).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${song.title} ($count)'),
              value: _roles.contains(role),
              onChanged: (on) => _toggle(role, on: on ?? false),
            ),
            SongPreview(script: s, song: song),
          ],
        ),
      ),
    );
  }
}
