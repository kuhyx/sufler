/// The phone's Firebase session, which the relay needs to reach the PC.
library;

/// Signed in to the shared sync account (or not), and how to become so.
abstract interface class PcSession {
  /// Whether a session is stored. Never throws.
  Future<bool> signedIn();

  /// Interactive sign-in (Google account picker); true when it worked.
  Future<bool> signIn();
}
