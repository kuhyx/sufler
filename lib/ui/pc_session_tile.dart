import 'dart:async';

import 'package:crdt_sync_flutter/crdt_sync_flutter.dart'
    show E2ePassphraseButton;
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/assist/pc_session.dart';
import 'package:sufler/assist/relay_seal.dart';

/// "Połącz z PC": the one-time Google sign-in the phone needs before it can
/// ask the PC (Claude, fresh voice clips) through Firebase. Once signed in,
/// a lock icon shows whether the relay's e2e key is open; tapping it enters
/// the shared crdt-sync passphrase (no text: crdt_sync_flutter's button).
class PcSessionTile extends StatefulWidget {
  /// Creates the tile for [session] (and [relayKey], when there is one).
  const new({required this.session, this.relayKey, super.key});

  /// The phone's Firebase session.
  final PcSession session;

  /// The relay's e2e key; null hides the lock.
  final RelayKey? relayKey;

  @override
  State<PcSessionTile> createState() => _PcSessionTileState();
}

class _PcSessionTileState extends State<PcSessionTile> {
  bool? _signedIn;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.session.signedIn().then((v) {
        if (mounted) setState(() => _signedIn = v);
        if (v) _checkKey();
      }, onError: (_) {}),
    );
  }

  /// Tries the key so the lock shows its state before the first request.
  void _checkKey({bool again = false}) {
    final key = widget.relayKey;
    if (key == null) return;
    unawaited(
      (again ? key.retry() : key.sealer()).then((_) {}, onError: (_) {}),
    );
  }

  Future<void> _signIn() async {
    setState(() => _busy = true);
    var ok = false;
    try {
      ok = await widget.session.signIn();
    } on Object {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _signedIn = ok;
      _failed = !ok;
    });
    if (ok) _checkKey();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = _signedIn;
    final status = context.statusColors;
    // State as a glyph + hue; the old sentences are spoken only.
    final subtitle = switch (signedIn) {
      null => const Align(
        alignment: AlignmentDirectional.centerStart,
        child: SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            semanticsLabel: 'Sprawdzam…',
          ),
        ),
      ),
      true => Icon(
        Icons.cloud_done_outlined,
        color: status.success,
        semanticLabel: 'Połączono: telefon pyta PC przez Firebase.',
      ),
      false when _failed => Icon(
        Icons.cloud_off_outlined,
        color: status.danger,
        semanticLabel:
            'Logowanie nie powiodło się. Spróbuj ponownie lub sprawdź sieć.',
      ),
      false => const Icon(
        Icons.cloud_outlined,
        semanticLabel:
            'Zaloguj się kontem Google synchronizacji, by z telefonu '
            'pytać PC o znaczenie słów i nagrywać poprawione kwestie.',
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.computer, semanticLabel: 'Połącz z PC'),
          subtitle: Align(
            alignment: AlignmentDirectional.centerStart,
            child: subtitle,
          ),
          trailing: switch ((signedIn, widget.relayKey)) {
            (false, _) => FilledButton(
              onPressed: _busy ? null : _signIn,
              child: const Icon(Icons.link, semanticLabel: 'Połącz'),
            ),
            (true, final key?) => ValueListenableBuilder<bool>(
              valueListenable: key.locked,
              builder: (_, locked, _) => E2ePassphraseButton(
                locked: locked,
                onSaved: () => _checkKey(again: true),
              ),
            ),
            _ => null,
          },
        ),
      ],
    );
  }
}
