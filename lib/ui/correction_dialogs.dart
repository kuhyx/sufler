import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/ui/labels.dart';

/// Result of [LineEditDialog].
typedef LineEdit = ({List<String> speakers, LineKind kind});

/// Result of [MergeDialog]: character [from] is really [into].
typedef MergePick = ({String from, String into});

/// Change one line's speakers and kind.
class LineEditDialog extends StatefulWidget {
  /// Creates the dialog.
  const LineEditDialog({required this.script, required this.line, super.key});

  /// The script (cast list).
  final Script script;

  /// The line being edited.
  final ScriptLine line;

  @override
  State<LineEditDialog> createState() => _LineEditDialogState();
}

class _LineEditDialogState extends State<LineEditDialog> {
  late List<String> _speakers = [...widget.line.speakers];
  late LineKind _kind = widget.line.kind;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Kwestia ${widget.line.index}'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.line.text),
          const SizedBox(height: AppSpacing.md),
          DropdownButton<LineKind>(
            key: const Key('kind'),
            isExpanded: true,
            value: _kind,
            items: [
              for (final k in LineKind.values)
                DropdownMenuItem(value: k, child: Text(kindLabel(k))),
            ],
            onChanged: (k) => setState(() => _kind = k ?? _kind),
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
                        : (_speakers.where((id) => id != c.id).toList()),
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
        onPressed: () => Navigator.of(
          context,
        ).pop<LineEdit>((speakers: _speakers, kind: _kind)),
        child: const Text('Zapisz'),
      ),
    ],
  );
}

/// Pick two characters to merge (alias A -> B).
class MergeDialog extends StatefulWidget {
  /// Creates the dialog.
  const MergeDialog({required this.script, super.key});

  /// The script (cast list).
  final Script script;

  @override
  State<MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends State<MergeDialog> {
  late String _from = widget.script.characters.last.id;
  late String _into = widget.script.characters.first.id;

  DropdownButton<String> _pick(
    Key key,
    String value,
    ValueChanged<String> on,
  ) => DropdownButton<String>(
    key: key,
    isExpanded: true,
    value: value,
    items: [
      for (final c in widget.script.characters)
        DropdownMenuItem(value: c.id, child: Text(c.name)),
    ],
    onChanged: (v) => setState(() => on(v ?? value)),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Scal postacie'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Postać (np. literówka)'),
        _pick(const Key('merge-from'), _from, (v) => _from = v),
        const SizedBox(height: AppSpacing.md),
        const Text('to naprawdę'),
        _pick(const Key('merge-into'), _into, (v) => _into = v),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Anuluj'),
      ),
      FilledButton(
        onPressed: _from == _into
            ? null
            : () => Navigator.of(
                context,
              ).pop<MergePick>((from: _from, into: _into)),
        child: const Text('Scal'),
      ),
    ],
  );
}
