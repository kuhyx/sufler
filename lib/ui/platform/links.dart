// coverage:ignore-file
// Platform glue over url_launcher; opens a real browser.
import 'package:url_launcher/url_launcher.dart';

/// Opens [uri] outside the app (the browser; a new tab on desktop).
Future<void> openExternalLink(Uri uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
