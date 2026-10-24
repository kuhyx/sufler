import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/range.dart';
import 'package:sufler/ui/labels.dart';

/// How the line picker builds its range.
enum PickMode {
  /// Tap the first and the last line.
  custom,

  /// Choose a start (play start or a section start), tap the last line.
  cumulative,
}

/// Picks a [LineRange] by tapping lines; pops with the range.
class LinePickerScreen extends StatefulWidget {
  /// Creates the picker.
  const new({required this.script, required this.mode, super.key});

  /// Pushes the picker; the chosen range, or null when backed out.
  static Future<LineRange?> pick(
    BuildContext context,
    Script script,
    PickMode mode,
  ) => Navigator.of(context).push(
    MaterialPageRoute<LineRange>(
      builder: (_) => LinePickerScreen(script: script, mode: mode),
    ),
  );

  /// The script.
  final Script script;

  /// Custom from-to or cumulative.
  final PickMode mode;

  @override
  State<LinePickerScreen> createState() => _LinePickerScreenState();
}

class _LinePickerScreenState extends State<LinePickerScreen> {
  int? _first;
  int _from = 0;

  bool get _cumulative => widget.mode == PickMode.cumulative;

  void _tap(int index) {
    if (_cumulative) {
      Navigator.of(context).pop(LineRange.cumulative(from: _from, upTo: index));
    } else if (_first == null) {
      setState(() => _first = index);
    } else {
      Navigator.of(context).pop(LineRange.custom(_first!, index));
    }
  }

  String get _hint {
    if (_cumulative) return 'Stuknij ostatnią kwestię.';
    return _first == null
        ? 'Stuknij pierwszą kwestię.'
        : 'Od $_first. Stuknij ostatnią kwestię.';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.script;
    // One entry per distinct start line (a song may start its scene).
    final starts = <int, String>{0: 'Od początku'};
    for (final sec in [...s.scenes, ...s.songs]) {
      starts.putIfAbsent(sec.start, () => 'Od: ${sec.title}');
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_cumulative ? 'Narastająco' : 'Własny zakres'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(_hint),
          ),
          if (_cumulative)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: DropdownButton<int>(
                key: const Key('cumulative-from'),
                isExpanded: true,
                value: _from,
                items: [
                  for (final e in starts.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _from = v ?? 0),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: s.lines.length,
              itemBuilder: (context, i) {
                final line = s.lines[i];
                final enabled = !_cumulative || i >= _from;
                return ListTile(
                  dense: true,
                  enabled: enabled,
                  selected: i == _first,
                  leading: Text('$i'),
                  title: Text(
                    line.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    line.isSpoken
                        ? speakerNames(s, line)
                        : kindLabel(line.kind),
                  ),
                  onTap: enabled ? () => _tap(i) : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
