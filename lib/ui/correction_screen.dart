import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/edits.dart';
import 'package:sufler/ui/correction_dialogs.dart';
import 'package:sufler/ui/labels.dart';
import 'package:sufler/ui/services.dart';

/// Browse lines and fix what the importer got wrong. Every edit is saved
/// to the library at once.
class CorrectionScreen extends StatefulWidget {
  /// Opens the stored script [scriptId].
  const CorrectionScreen({required this.scriptId, super.key});

  /// Id of the script in the library.
  final String scriptId;

  @override
  State<CorrectionScreen> createState() => _CorrectionScreenState();
}

class _CorrectionScreenState extends State<CorrectionScreen> {
  Script? _script;

  Services get _svc => ServicesScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_script == null) unawaited(_load());
  }

  Future<void> _load() async {
    final s = await _svc.library.loadScript(widget.scriptId);
    if (mounted) setState(() => _script = s);
  }

  Future<void> _save(Script s) async {
    setState(() => _script = s);
    await _svc.library.saveScript(s);
  }

  Future<void> _editLine(ScriptLine line) async {
    final edit = await showDialog<LineEdit>(
      context: context,
      builder: (_) => LineEditDialog(script: _script!, line: line),
    );
    if (edit == null) return;
    await _save(
      editLine(_script!, line.index, speakers: edit.speakers, kind: edit.kind),
    );
  }

  Future<void> _merge() async {
    final pick = await showDialog<MergePick>(
      context: context,
      builder: (_) => MergeDialog(script: _script!),
    );
    if (pick == null || pick.from == pick.into) return;
    await _save(mergeCharacter(_script!, from: pick.from, into: pick.into));
    final lib = _svc.library;
    final prefs = await lib.loadPrefs(widget.scriptId);
    await lib.savePrefs(
      widget.scriptId,
      prefs.copyWith(
        roles: renameRole(prefs.roles, from: pick.from, into: pick.into),
      ),
    );
    if (mounted) showToast(context, 'Postacie scalone');
  }

  @override
  Widget build(BuildContext context) {
    final s = _script;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Popraw tekst'),
        actions: [
          IconButton(
            tooltip: 'Scal postacie',
            icon: const Icon(Icons.merge_type),
            onPressed: s == null || s.characters.length < 2 ? null : _merge,
          ),
        ],
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kProseMaxWidth),
                child: ListView.builder(
                  itemCount: s.lines.length,
                  itemBuilder: (context, i) => _tile(s, s.lines[i]),
                ),
              ),
            ),
    );
  }

  Widget _tile(Script s, ScriptLine line) => ListTile(
    leading: Text('${line.index}'),
    title: Text(line.text, maxLines: 3, overflow: TextOverflow.ellipsis),
    subtitle: Text('${kindLabel(line.kind)} · ${speakerNames(s, line)}'),
    trailing: const Icon(Icons.edit_outlined),
    onTap: () => _editLine(line),
  );
}
