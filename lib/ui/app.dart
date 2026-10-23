import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/ui/library_screen.dart';
import 'package:sufler/ui/services.dart';

/// Root widget. Theming comes entirely from `design_system`.
class SuflerApp extends StatelessWidget {
  /// Creates the app over [services].
  const SuflerApp({required this.services, super.key});

  /// Everything outside the UI.
  final Services services;

  @override
  Widget build(BuildContext context) => ServicesScope(
    services: services,
    child: MaterialApp(
      title: 'Sufler',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: const LibraryScreen(),
    ),
  );
}
