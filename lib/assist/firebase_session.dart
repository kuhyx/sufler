/// The phone's Firebase session (tutor's `lib/sync/auth.dart` pattern):
/// Google ID token -> Firebase refresh token in the Android keystore ->
/// short-lived ID tokens for every RTDB request.
library;

import 'dart:developer';

import 'package:crdt_sync/crdt_sync.dart'
    show FirebaseCredentialStore, FirebaseTokenProvider, SecureCredentialStore;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sufler/assist/firebase_config.dart';
import 'package:sufler/assist/pc_session.dart';

/// Fetches a Google ID token for the picked account (null: cancelled).
typedef GoogleTokenFetcher = Future<String?> Function(String serverClientId);

/// [PcSession] over crdt_sync's token provider.
class FirebaseSession implements PcSession {
  /// Creates the session. Tests pass a memory [store] and fake [httpClient].
  new({
    required this.config,
    required FirebaseCredentialStore store,
    required this.googleToken,
    http.Client? httpClient,
  }) : provider = FirebaseTokenProvider(
         apiKey: config.apiKey,
         store: store,
         httpClient: httpClient,
       );

  /// The build's Firebase identifiers.
  final FirebaseConfig config;

  /// The platform's Google account picker.
  final GoogleTokenFetcher googleToken;

  /// Mints ID tokens, refreshing from the stored refresh token.
  final FirebaseTokenProvider provider;

  @override
  Future<bool> signedIn() async {
    if (!config.isComplete) return false;
    try {
      return await provider.hasSession();
    } on Object catch (error) {
      log('session probe failed; signed out', level: 1000, error: error);
      return false;
    }
  }

  @override
  Future<bool> signIn() async {
    if (!config.isComplete) {
      log('no Firebase config compiled in (write_firebase_config)', level: 900);
      return false;
    }
    try {
      final token = await googleToken(config.serverClientId);
      if (token == null) return false;
      // expectedUid: picking another Google account must not sign up a
      // second user; nothing is stored then.
      await provider.signInWithGoogle(
        idToken: token,
        expectedUid: config.syncUid,
      );
      return true;
    } on Object catch (error) {
      log('Google sign-in failed', level: 1000, error: error);
      return false;
    }
  }

  /// A currently valid ID token (throws when signed out or revoked).
  Future<String> idToken() => provider.idToken();
}

/// The keystore-backed credential store (Android keystore).
// coverage:ignore-start
FirebaseCredentialStore secureCredentialStore() {
  const secure = FlutterSecureStorage();
  return SecureCredentialStore(
    read: (k) => secure.read(key: k),
    write: (k, v) => secure.write(key: k, value: v),
    delete: (k) => secure.delete(key: k),
    key: 'sufler.firebase.credentials',
  );
}

// coverage:ignore-end
