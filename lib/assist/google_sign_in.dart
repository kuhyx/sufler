/// One-tap Google sign-in on Android (tutor's `google_sign_in_backend.dart`).
///
/// Through `google_account_token` (AccountManager, no Play Services SDK in
/// the APK). Off Android the plugin returns null, so the desktop (web) build
/// starts offline and never signs in.
///
/// The client id is the project's **Web** OAuth client: Android must request
/// a token minted for it, or Firebase answers `audience mismatch`. The app's
/// own Android OAuth client (package + release SHA-1) must exist in the
/// project, or the chooser fails (`scripts/register_oauth_client.sh`).
library;

import 'package:google_account_token/google_account_token.dart' as plugin;

/// A Google ID token for the account the user picks, or null.
Future<String?> googleIdToken(String serverClientId) =>
    plugin.googleIdToken(serverClientId: serverClientId);
