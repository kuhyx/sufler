import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Import from a file or a Google Docs link.
class ImportPanel extends StatefulWidget {
  /// Creates the panel.
  const new({
    required this.busy,
    required this.onFile,
    required this.onLink,
    super.key,
  });

  /// An import is running (buttons disabled, progress shown).
  final bool busy;

  /// "Importuj plik".
  final VoidCallback onFile;

  /// "Importuj link" with the pasted URL.
  final ValueChanged<String> onLink;

  @override
  State<ImportPanel> createState() => _ImportPanelState();
}

class _ImportPanelState extends State<ImportPanel> {
  final _url = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _link() {
    final url = _url.text.trim();
    if (url.isNotEmpty) widget.onLink(url);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        onPressed: widget.busy ? null : widget.onFile,
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
        onSubmitted: (_) => _link(),
      ),
      const SizedBox(height: AppSpacing.sm),
      OutlinedButton.icon(
        onPressed: widget.busy ? null : _link,
        icon: const Icon(Icons.link),
        label: const Text('Importuj link'),
      ),
      if (widget.busy) const LinearProgressIndicator(),
    ],
  );
}
