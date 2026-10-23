import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/script.dart';

/// Result of [LineTextDialog].
typedef LineTextEdit = ({String text, List<String> speakers});

/// Correct one line on the go: its text and who says it.
class LineTextDialog extends StatefulWidget {
  /// Creates the dialog.
  const new({required this.script, required this.line, super.key});

  /// The script (cast list).
  final Script script;

  /// The line being corrected.
  final ScriptLine line;

  @override
  State<LineTextDialog> createState() => _LineTextDialogState();
}

class _LineTextDialogState extends State<LineTextDialog> {
  late final _text = TextEditingController(text: widget.line.text);
  late List<String> _speakers = [...widget.line.speakers];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _valid => hasWords(_text.text);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Kwestia ${widget.line.index}'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('line-text'),
            controller: _text,
            maxLines: null,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tekst'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('Mówią'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final c in widget.script.characters)
                FilterChip(
                  label: Text(c.name),
                  selected: _speakers.contains(c.id),
                  onSelected: (on) => setState(
                    () => _speakers = on
                        ? [..._speakers, c.id]
                        : _speakers.where((id) => id != c.id).toList(),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Anuluj'),
      ),
      FilledButton(
        onPressed: _valid
            ? () => Navigator.of(context).pop<LineTextEdit>((
                text: _text.text.trim(),
                speakers: _speakers,
              ))
            : null,
        child: const Text('Zapisz'),
      ),
    ],
  );
}
