import 'package:sufler/assist/assistant.dart';
import 'package:sufler/assist/device_id.dart';
import 'package:sufler/assist/firebase_config.dart';
import 'package:sufler/assist/firebase_session.dart';
import 'package:sufler/assist/google_sign_in.dart';
import 'package:sufler/assist/pc_session.dart';
import 'package:sufler/assist/relay_assistant.dart';
import 'package:sufler/assist/rtdb_client.dart';
import 'package:sufler/storage/store.dart';

// Bootstrap wiring for the real phone; the parts are tested on fakes.
// coverage:ignore-start
FirebaseSession? _session;

/// Android's one Firebase session (shared by the relay and the tile).
PcSession? openPcSession() => _firebase();

FirebaseSession _firebase() => _session ??= FirebaseSession(
  config: FirebaseConfig.compiled,
  store: secureCredentialStore(),
  googleToken: googleIdToken,
);

/// Android: requests to the PC go through Firebase RTDB.
Assistant openAssistant(Store store) {
  final session = _firebase();
  return RelayAssistant(
    rtdb: RtdbClient(
      databaseUrl: FirebaseConfig.compiled.databaseUrl,
      idToken: session.idToken,
    ),
    deviceId: () => deviceId(store),
    session: session,
  );
}

// coverage:ignore-end
