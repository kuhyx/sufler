import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/ui/script_screen.dart';
import 'package:sufler/ui/services.dart';

/// Imported scripts, plus import from a file or a Google Docs link.
class LibraryScreen extends StatefulWidget {
  /// Creates the screen.
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _url = TextEditingController();
  List<Script>? _scripts;
  bool _busy = false;

  Services get _services => ServicesScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scripts == null) unawaited(_reload());
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
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

  Future<void> _importFile() => _import(() async {
    final file = await _services.files.pick(['pdf', 'docx', 'odt', 'txt']);
    if (file == null) return null;
    return await _services.importDocument(
      fileName: file.name,
      bytes: file.bytes,
    );
  });

  Future<void> _importLink() {
    final url = _url.text.trim();
    if (url.isEmpty) return Future.value();
    return _import(() => _services.importGoogleDoc(url));
  }

  Future<void> _open(String id) async {
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
      appBar: AppBar(title: const Text('Sufler')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kProseMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _importPanel(),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader('Twoje skrypty'),
              if (scripts == null)
                const Center(child: CircularProgressIndicator())
              else if (scripts.isEmpty)
                const EmptyState(
                  icon: Icons.theater_comedy_outlined,
                  title: 'Brak skryptów',
                  message: 'Zaimportuj sztukę z pliku albo z Google Docs.',
                )
              else
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

  Widget _importPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        onPressed: _busy ? null : _importFile,
        icon: const Icon(Icons.upload_file),
        label: const Text('Importuj plik'),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'PDF, DOCX, ODT lub TXT',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: AppSpacing.md),
      TextField(
        key: const Key('gdoc-url'),
        controller: _url,
        decoration: const InputDecoration(
          labelText: 'Link do Google Docs',
          hintText: 'https://docs.google.com/document/d/…',
        ),
        onSubmitted: (_) => _importLink(),
      ),
      const SizedBox(height: AppSpacing.sm),
      OutlinedButton.icon(
        onPressed: _busy ? null : _importLink,
        icon: const Icon(Icons.link),
        label: const Text('Importuj link'),
      ),
      if (_busy) const LinearProgressIndicator(),
    ],
  );
}
