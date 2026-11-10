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
      theme: _quiet(withBundledFonts(buildLightTheme())),
      darkTheme: _quiet(withBundledFonts(buildDarkTheme())),
      home: const LibraryScreen(),
    ),
  );
}

/// Framework tooltips ("Back" on hover, long-press labels) are painted words
/// (textgate). They never trigger: no tap or long-press, and a hover delay
/// nobody waits out. Unlike TooltipVisibility(false), the message stays the
/// control's spoken name.
ThemeData _quiet(ThemeData theme) => theme.copyWith(
  tooltipTheme: theme.tooltipTheme.copyWith(
    triggerMode: TooltipTriggerMode.manual,
    waitDuration: const Duration(days: 1),
  ),
);
