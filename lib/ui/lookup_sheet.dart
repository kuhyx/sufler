import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/assist/ask.dart';
import 'package:sufler/ui/lookup_text.dart';

/// sjp.pwn.pl search for [words].
Uri sjpLink(String words) =>
    Uri.parse('https://sjp.pwn.pl/szukaj/${Uri.encodeComponent(words)}.html');

/// Polish Wiktionary entry for [words].
Uri wiktionaryLink(String words) =>
    Uri.parse('https://pl.wiktionary.org/wiki/${Uri.encodeComponent(words)}');

/// A long-pressed word: dictionaries, and "Zapytaj Claude" about the word
/// or its whole sentence ([ask] starts the request, which outlives the
/// sheet).
class LookupSheet extends StatefulWidget {
  /// Creates the sheet for [pick].
  const new({
    required this.pick,
    required this.openLink,
    required this.ask,
    super.key,
  });

  /// The word and its sentence.
  final LookupPick pick;

  /// Opens a web page.
  final Future<void> Function(Uri uri) openLink;

  /// Sends a question about the given words.
  final Ask Function(String selection) ask;

  @override
  State<LookupSheet> createState() => _LookupSheetState();
}

class _LookupSheetState extends State<LookupSheet> {
  bool _sentence = false;
  Ask? _ask;

  String get _words => _sentence ? widget.pick.sentence : widget.pick.word;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ask?.removeListener(_changed);
    super.dispose();
  }

  void _send() =>
      setState(() => _ask = widget.ask(_words)..addListener(_changed));

  Widget _answer(BuildContext context, Ask a) {
    final style = Theme.of(context).textTheme.bodyMedium;
    if (a.answer case final text?) return Text(text, style: style);
    if (a.error case final why?) return Text('Nie udało się: $why');
    if (a.offline) {
      return const Row(
        children: [
          Icon(Icons.cloud_off),
          SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(offlineAskMessage)),
        ],
      );
    }
    return const Center(child: CircularProgressIndicator());
  }

  @override
  Widget build(BuildContext context) {
    final pick = widget.pick;
    final ask = _ask;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('„$_words”', style: Theme.of(context).textTheme.titleMedium),
            if (pick.sentence != pick.word && ask == null)
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  ChoiceChip(
                    label: const Text('słowo'),
                    selected: !_sentence,
                    onSelected: (_) => setState(() => _sentence = false),
                  ),
                  ChoiceChip(
                    label: const Text('całe zdanie'),
                    selected: _sentence,
                    onSelected: (_) => setState(() => _sentence = true),
                  ),
                ],
              ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Słownik'),
              subtitle: const Text('sjp.pwn.pl'),
              onTap: () => unawaited(widget.openLink(sjpLink(_words))),
            ),
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('Wikisłownik'),
              subtitle: const Text('pl.wiktionary.org'),
              onTap: () => unawaited(widget.openLink(wiktionaryLink(_words))),
            ),
            if (ask == null)
              FilledButton.icon(
                onPressed: _send,
                icon: const Icon(Icons.lightbulb_outline),
                label: const Text('Zapytaj Claude'),
              )
            else
              _answer(context, ask),
          ],
        ),
      ),
    );
  }
}
