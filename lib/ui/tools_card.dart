import 'dart:async';
import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/audio/pack_check.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/storage/pack_zip.dart';
import 'package:sufler/ui/services.dart';

/// Corrections, timings, Anki export and voice packs.
class ToolsCard extends StatefulWidget {
  /// Creates the card.
  const new({
    required this.script,
    required this.roles,
    required this.pack,
    required this.canRender,
    required this.onPack,
    required this.onCorrect,
    required this.onTimings,
    this.onRefreshParse,
    super.key,
  });

  /// The script.
  final Script script;

  /// Picked roles (the Anki deck is built for them).
  final Set<Role> roles;

  /// Loaded voice pack, if any.
  final AudioPack? pack;

  /// Whether "Generate voices" is offered.
  final bool canRender;

  /// A new pack was stored.
  final ValueChanged<AudioPack> onPack;

  /// Open the correction screen.
  final VoidCallback onCorrect;

  /// Open the timings screen.
  final VoidCallback onTimings;

  /// Pick the document to refresh an old parse; null hides the item.
  final VoidCallback? onRefreshParse;

  @override
  State<ToolsCard> createState() => _ToolsCardState();
}

class _ToolsCardState extends State<ToolsCard> {
  ({int done, int total})? _progress;

  Services get _svc => ServicesScope.of(context);

  Future<void> _guard(String what, Future<void> Function() body) async {
    try {
      await body();
    } on Object catch (e) {
      final why = e is FormatException ? e.message : '$e';
      if (mounted) showError(context, '$what: $why');
    }
  }

  Future<void> _exportAnki() => _guard('Eksport nie powiódł się', () async {
    if (widget.roles.isEmpty) {
      showError(context, 'Wybierz co najmniej jedną rolę');
      return;
    }
    final bytes = await _svc.exportApkg(
      widget.script,
      widget.roles,
      audio: widget.pack,
    );
    await _svc.files.save(
      '${widget.script.title}.apkg',
      bytes,
      'application/octet-stream',
    );
  });

  Future<void> _store(AudioPack pack, {Uint8List? zip}) async {
    final checked = checkPack(widget.script, pack);
    if (checked.pack == null) throw FormatException(checked.message!);
    await _svc.library.savePack(
      widget.script.id,
      zip ?? packToZip(widget.script, pack),
    );
    widget.onPack(pack);
    if (!mounted) return;
    showToast(context, 'Głosy zapisane (${pack.length} kwestii)');
    if (checked.message != null) showError(context, checked.message!);
  }

  Future<void> _render() => _guard('Generowanie nie powiodło się', () async {
    setState(() => _progress = (done: 0, total: 0));
    try {
      await for (final p in _svc.renderPack(widget.script)) {
        if (mounted) setState(() => _progress = (done: p.done, total: p.total));
        final pack = p.pack;
        if (pack != null) await _store(pack);
      }
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  });

  Future<void> _importPack() => _guard('Zła paczka audio', () async {
    final file = await _svc.files.pick(['zip']);
    if (file == null) return;
    final pack = AudioPack.fromZip(file.bytes);
    if (pack.scriptId != widget.script.id) {
      throw const FormatException('paczka jest dla innego skryptu');
    }
    await _store(pack, zip: file.bytes);
  });

  @override
  Widget build(BuildContext context) {
    final pack = widget.pack;
    final progress = _progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Narzędzia'),
        if (widget.onRefreshParse case final refresh?)
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Odśwież parsowanie: wskaż plik'),
            subtitle: const Text(
              'skrypt ma starszą wersję parsowania; czasy, nagrania i oceny '
              'zostaną',
            ),
            onTap: refresh,
          ),
        ListTile(
          leading: const Icon(Icons.edit_note),
          title: const Text('Popraw tekst'),
          subtitle: const Text('mówiący, rodzaj kwestii, scalanie postaci'),
          onTap: widget.onCorrect,
        ),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Czasy i nagrania'),
          subtitle: const Text('długość pauzy, nagraj siebie'),
          onTap: widget.onTimings,
        ),
        ListTile(
          leading: const Icon(Icons.style_outlined),
          title: const Text('Eksportuj talię Anki'),
          onTap: _exportAnki,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('Głosy', style: Theme.of(context).textTheme.labelLarge),
        Text(
          pack == null
              ? 'Brak paczki: partnerów czyta syntezator urządzenia.'
              : 'Paczka: ${pack.engine}, ${pack.length} kwestii.',
        ),
        if (widget.canRender)
          ListTile(
            leading: const Icon(Icons.record_voice_over),
            title: const Text('Generuj głosy'),
            enabled: progress == null,
            onTap: _render,
          ),
        if (progress != null)
          LinearProgressIndicator(
            value: progress.total == 0 ? null : progress.done / progress.total,
          ),
        ListTile(
          leading: const Icon(Icons.folder_zip_outlined),
          title: const Text('Importuj paczkę audio (.zip)'),
          onTap: _importPack,
        ),
      ],
    );
  }
}
