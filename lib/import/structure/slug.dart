const _fold = {
  'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n', 'ó': 'o', 'ś': 's', //
  'ź': 'z', 'ż': 'z', 'á': 'a', 'é': 'e', 'í': 'i', 'ú': 'u', 'ü': 'u',
  'ö': 'o', 'ä': 'a', 'č': 'c', 'š': 's', 'ž': 'z', 'ř': 'r', 'ý': 'y',
};

/// ASCII slug of [text] with Polish letters folded ("Żagiewka" -> zagiewka).
String slugify(String text) {
  final out = StringBuffer();
  for (final ch in text.toLowerCase().split('')) {
    out.write(_fold[ch] ?? ch);
  }
  final slug = out
      .toString()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'x' : slug;
}

/// Hands out unique slugs: a repeated title gets `-2`, `-3`...
class SlugRegistry {
  final Set<String> _used = {};

  /// A slug for [title] not handed out before.
  String take(String title) {
    final base = slugify(title);
    var id = base;
    for (var n = 2; !_used.add(id); n++) {
      id = '$base-$n';
    }
    return id;
  }
}
