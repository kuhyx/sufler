import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/assist/pc_session.dart';

/// "Połącz z PC": the one-time Google sign-in the phone needs before it can
/// ask the PC (Claude, fresh voice clips) through Firebase.
class PcSessionTile extends StatefulWidget {
  /// Creates the tile for [session].
  const new({required this.session, super.key});

  /// The phone's Firebase session.
  final PcSession session;

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
      }, onError: (_) {}),
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
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = _signedIn;
    final subtitle = switch (signedIn) {
      null => 'Sprawdzam…',
      true => 'Połączono: telefon pyta PC przez Firebase.',
      false when _failed =>
        'Logowanie nie powiodło się. Spróbuj ponownie lub sprawdź sieć.',
      false =>
        'Zaloguj się kontem Google synchronizacji, by z telefonu '
            'pytać PC o znaczenie słów i nagrywać poprawione kwestie.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        const SectionHeader('PC (Claude i głosy)'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Połącz z PC'),
          subtitle: Text(subtitle),
          trailing: signedIn == false
              ? FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: const Text('Połącz'),
                )
              : null,
        ),
      ],
    );
  }
}
