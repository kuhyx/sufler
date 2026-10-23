/// Fonts shipped with the app (pubspec `fonts:`), so the desktop web build
/// never fetches one from a CDN.
library;

import 'package:flutter/material.dart';

/// The default text family. The web engine downloads "Roboto" at start-up
/// unless a family of exactly this name is bundled.
const bundledFont = 'Roboto';

/// Fallback for glyphs Roboto lacks ("♪" in unheaded song titles); without
/// it the web engine fetches a Noto font for them.
const symbolFont = 'Noto Sans Symbols';

/// [theme] with every text style on the bundled fonts.
ThemeData withBundledFonts(ThemeData theme) => theme.copyWith(
  textTheme: theme.textTheme.apply(
    fontFamily: bundledFont,
    fontFamilyFallback: const [symbolFont],
  ),
  primaryTextTheme: theme.primaryTextTheme.apply(
    fontFamily: bundledFont,
    fontFamilyFallback: const [symbolFont],
  ),
);
