/// The Firebase identifiers the phone relay talks to.
///
/// The literal values live in the gitignored `firebase_local.dart`, written
/// by `dart run tool/write_firebase_config.dart` (CI: `--placeholder`). This
/// repo is public, so the uid / API key never appear in source.
library;

import 'package:sufler/assist/firebase_local.dart' as local;

/// The four identifiers the relay needs.
class FirebaseConfig {
  /// Creates a config; tests pass fakes.
  const new({
    required this.apiKey,
    required this.databaseUrl,
    required this.syncUid,
    required this.serverClientId,
  });

  /// The values compiled into this build.
  static const FirebaseConfig compiled = FirebaseConfig(
    apiKey: local.kFirebaseApiKey,
    databaseUrl: local.kFirebaseDatabaseUrl,
    syncUid: local.kFirebaseSyncUid,
    serverClientId: local.kGoogleServerClientId,
  );

  /// Web API key of the kuhy-syncs project.
  final String apiKey;

  /// Regional RTDB URL.
  final String databaseUrl;

  /// The uid the sync account must resolve to: a wrong Google account
  /// would sign up a second user; the sign-in refuses it.
  final String syncUid;

  /// Google *Web* OAuth client id, used as the ID-token audience.
  final String serverClientId;

  /// Whether the relay can sign in and reach the database at all.
  bool get isComplete =>
      apiKey.isNotEmpty &&
      databaseUrl.isNotEmpty &&
      syncUid.isNotEmpty &&
      serverClientId.isNotEmpty;
}
