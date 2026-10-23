import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/ui/fonts.dart';
import 'package:sufler/ui/library_screen.dart';
import 'package:sufler/ui/services.dart';

/// Root widget. Theming comes from `design_system`, on bundled fonts.
class SuflerApp extends StatelessWidget {
  /// Creates the app over [services].
  const new({required this.services, super.key});

  /// Everything outside the UI.
  final Services services;

  @override
  Widget build(BuildContext context) => ServicesScope(
    services: services,
    child: MaterialApp(
      title: 'Sufler',
      theme: withBundledFonts(buildLightTheme()),
      darkTheme: withBundledFonts(buildDarkTheme()),
      home: const LibraryScreen(),
    ),
  );
}
