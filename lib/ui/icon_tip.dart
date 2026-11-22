import 'package:material_ui/material_ui.dart';

/// One word naming what an app icon stands for, on hover (desktop, web) or
/// long-press (phone): the one painted word textgate allows an icon.
///
/// The app theme silences framework tooltips (see `appTheme`), and an
/// IconButton's own `tooltip:` inherits that, so the word needs an explicit
/// Tooltip whose trigger and delay override the theme. Keep the icon's
/// semanticLabel: it stays the control's spoken name.
class IconTip extends StatelessWidget {
  /// Shows [word] over [child].
  const new(this.word, {required this.child, super.key});

  /// The word: one, no spaces or punctuation, at most 20 characters.
  final String word;

  /// The icon control it names.
  final Widget child;

  /// Hover delay: long enough not to flash while the pointer passes.
  static const wait = Duration(milliseconds: 500);

  @override
  Widget build(BuildContext context) => Tooltip(
    message: word,
    triggerMode: TooltipTriggerMode.longPress,
    waitDuration: wait,
    excludeFromSemantics: true,
    child: child,
  );
}
