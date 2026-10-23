import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/ui/import_panel.dart';
import 'package:sufler/ui/script_screen.dart';
import 'package:sufler/ui/services.dart';

/// Imported scripts. On start it opens the last used script straight away
/// (back from it lands here); importing is the "+" action.
class LibraryScreen extends StatefulWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Script>? _scripts;
  bool _busy = false;
  bool _started = false;

  Services get _services => ServicesScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_start());
  }

  Future<void> _start() async {
    final id = await _services.library.startScriptId();
    await _reload();
    if (id != null && mounted) await _open(id);
  }

  Future<void> _reload() async {
    final list = await _services.library.scripts();
    if (mounted) setState(() => _scripts = list);
  }

  Future<void> _import(Future<Script?> Function() load) async {
    setState(() => _busy = true);
    try {
      final script = await load();
      if (script == null) return;
      final existing = await _services.library.loadScript(script.id);
      if (existing == null) await _services.library.saveScript(script);
      await _reload();
      if (mounted) await _open(script.id);
    } on Object catch (e) {
      if (mounted) showError(context, 'Import nie powiódł się: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _importFile() => unawaited(
    _import(() async {
      final file = await _services.files.pick(['pdf', 'docx', 'odt', 'txt']);
      if (file == null) return null;
      return await _services.importDocument(
        fileName: file.name,
        bytes: file.bytes,
      );
    }),
  );

  void _importLink(String url) =>
      unawaited(_import(() => _services.importGoogleDoc(url)));

  Future<void> _openImport() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md + MediaQuery.viewInsetsOf(sheet).bottom,
      ),
      child: ImportPanel(
        busy: false,
        onFile: () {
          Navigator.of(sheet).pop();
          _importFile();
        },
        onLink: (url) {
          Navigator.of(sheet).pop();
          _importLink(url);
        },
      ),
    ),
  );

  Future<void> _open(String id) async {
    await _services.library.rememberScript(id);
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ScriptScreen(scriptId: id)));
    await _reload();
  }

  Future<void> _delete(Script s) async {
    final ok = await confirmDestructive(
      context,
      title: 'Usunąć „${s.title}”?',
      message: 'Znikną też poprawki, czasy, nagrania i głosy tego skryptu.',
      confirmLabel: 'Usuń',
      cancelLabel: 'Anuluj',
    );
    if (!ok) return;
    await _services.library.deleteScript(s.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scripts = _scripts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sufler'),
        actions: [
          if (scripts != null && scripts.isNotEmpty)
            IconButton(
              tooltip: 'Importuj',
              icon: const Icon(Icons.add),
              onPressed: _busy ? null : _openImport,
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kProseMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const SectionHeader('Twoje skrypty'),
              if (_busy) const LinearProgressIndicator(),
              if (scripts == null)
                const Center(child: CircularProgressIndicator())
              else if (scripts.isEmpty) ...[
                const EmptyState(
                  icon: Icons.theater_comedy_outlined,
                  title: 'Brak skryptów',
                  message: 'Zaimportuj sztukę z pliku albo z Google Docs.',
                ),
                ImportPanel(
                  busy: _busy,
                  onFile: _importFile,
                  onLink: _importLink,
                ),
              ] else
                for (final s in scripts) _tile(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(Script s) => ListTile(
    title: Text(s.title),
    subtitle: Text(
      '${s.source} · ${s.lines.where((l) => l.isSpoken).length} kwestii',
    ),
    onTap: () => _open(s.id),
    trailing: IconButton(
      tooltip: 'Usuń',
      icon: const Icon(Icons.delete_outline),
      onPressed: () => _delete(s),
    ),
  );
}
