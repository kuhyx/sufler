import 'dart:async';
import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/audio/pack_check.dart';
import 'package:sufler/model/line_note.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/storage/pack_zip.dart';
import 'package:sufler/ui/feedback.dart';
import 'package:sufler/ui/labels.dart';
import 'package:sufler/ui/option_segments.dart';
import 'package:sufler/ui/option_tiles.dart';
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
    this.notes = const {},
    this.onRefreshParse,
    super.key,
  });

  /// The script.
  final Script script;

  /// Picked roles (the Anki deck is built for them).
  final Set<Role> roles;

  /// Loaded voice pack, if any.
  final AudioPack? pack;

  /// The assistant's notes per line (they go on the Anki card backs).
  final Map<int, List<LineNote>> notes;

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
      if (mounted) showFailure(context, '$what: $why');
    }
  }

  Future<void> _exportAnki() => _guard('Eksport nie powiódł się', () async {
    if (widget.roles.isEmpty) {
      showFailure(context, 'Wybierz co najmniej jedną rolę');
      return;
    }
    final bytes = await _svc.exportApkg(
      widget.script,
      widget.roles,
      audio: widget.pack,
      notes: widget.notes,
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
    showDone(context, 'Głosy zapisane (${pack.length} kwestii)');
    if (checked.message != null) showFailure(context, checked.message!);
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
    final script = OptionGroup(
      icon: Icons.description_outlined,
      label: groupScript,
      children: [
        if (widget.onRefreshParse case final refresh?)
          ActionTile(
            key: const Key('refresh-parse'),
            icon: Icons.refresh,
            title: const Icon(
              Icons.refresh,
              semanticLabel: 'Odśwież parsowanie: wskaż plik',
            ),
            info:
                'skrypt ma starszą wersję parsowania; czasy, nagrania i oceny '
                'zostaną',
            onTap: refresh,
          ),
        ActionTile(
          key: const Key('correct-text'),
          icon: Icons.edit_note,
          title: const Icon(Icons.edit_note, semanticLabel: 'Popraw tekst'),
          onTap: widget.onCorrect,
        ),
        ActionTile(
          key: const Key('timings'),
          icon: Icons.timer_outlined,
          title: const Icon(
            Icons.timer_outlined,
            semanticLabel: 'Czasy i nagrania',
          ),
          onTap: widget.onTimings,
        ),
        ActionTile(
          key: const Key('export-anki'),
          icon: Icons.style_outlined,
          title: const Icon(
            Icons.style_outlined,
            semanticLabel: 'Eksportuj talię Anki',
          ),
          onTap: _exportAnki,
        ),
      ],
    );
    final voices = OptionGroup(
      icon: Icons.record_voice_over_outlined,
      label: groupVoices,
      children: [
        Row(
          key: const Key('pack-state'),
          spacing: AppSpacing.sm,
          children: pack == null
              ? const [
                  Icon(
                    Icons.phone_android,
                    semanticLabel:
                        'Brak paczki: partnerów czyta syntezator urządzenia.',
                  ),
                ]
              : [
                  Icon(
                    Icons.library_music_outlined,
                    semanticLabel:
                        'Paczka: ${pack.engine}, ${pack.length} kwestii.',
                  ),
                  Text('${pack.length}'),
                ],
        ),
        if (progress != null)
          LinearProgressIndicator(
            value: progress.total == 0 ? null : progress.done / progress.total,
          ),
        if (widget.canRender)
          ActionTile(
            key: const Key('generate-voices'),
            icon: Icons.record_voice_over,
            title: const Icon(
              Icons.record_voice_over,
              semanticLabel: 'Generuj głosy',
            ),
            onTap: progress == null ? _render : null,
          ),
        ActionTile(
          key: const Key('import-audio'),
          icon: Icons.folder_zip_outlined,
          title: const Icon(
            Icons.folder_zip_outlined,
            semanticLabel: 'Importuj paczkę audio (.zip)',
          ),
          onTap: _importPack,
        ),
      ],
    );
    return OptionSegments(groups: [script, voices]);
  }
}
