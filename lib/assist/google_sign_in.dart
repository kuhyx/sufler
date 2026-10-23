/// One-tap Google sign-in on Android (tutor's `google_sign_in_backend.dart`).
///
/// Through the platform interface and `google_sign_in_android` only, not
/// the `google_sign_in` app package: that one pulls in `google_sign_in_web`,
/// whose plugin constructor loads Google's GIS script at startup, and the
/// desktop (web) build must start offline and never sign in.
///
/// The client id is the project's **Web** OAuth client: Android must request
/// a token minted for it, or Firebase answers `audience mismatch`. The app's
/// own Android OAuth client (package + release SHA-1) must exist in the
/// project, or the picker fails (`scripts/register_oauth_client.sh`).
library;

import 'dart:developer';

import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

bool _initialized = false;

/// A Google ID token for the account the user picks, or null.
// The OS account picker is a platform channel `flutter test` has no
// binding for.
// coverage:ignore-start
Future<String?> googleIdToken(String serverClientId) async {
  if (serverClientId.isEmpty) return null;
  final google = GoogleSignInPlatform.instance;
  try {
    if (!_initialized) {
      await google.init(InitParameters(serverClientId: serverClientId));
      _initialized = true;
    }
    if (!google.supportsAuthenticate()) return null;
    final result = await google.authenticate(const AuthenticateParameters());
    return result.authenticationTokens.idToken;
  } on GoogleSignInException catch (error, stackTrace) {
    // The user dismissing the picker and a configuration failure
    // (unregistered SHA-1, wrong client id) arrive the same way: log it.
    log(
      'Google sign-in did not complete',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
}

// coverage:ignore-end
