import 'package:flutter/material.dart';

void main() => runApp(const SuflerApp());

/// Root widget. Screens are wired in by the UI layer.
class SuflerApp extends StatelessWidget {
  /// Creates the app.
  const SuflerApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'Sufler',
    home: Scaffold(body: Center(child: Text('Sufler'))),
  );
}
