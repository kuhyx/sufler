import 'package:crdt_sync_flutter/crdt_sync_flutter.dart'
    show kE2ePassphraseKey, kSecureStorage, keystoreKeyCache;
import 'package:sufler/assist/assistant.dart';
import 'package:sufler/assist/device_id.dart';
import 'package:sufler/assist/firebase_config.dart';
import 'package:sufler/assist/firebase_session.dart';
import 'package:sufler/assist/google_sign_in.dart';
import 'package:sufler/assist/pc_session.dart';
import 'package:sufler/assist/relay_assistant.dart';
import 'package:sufler/assist/relay_seal.dart';
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

RtdbClient? _rtdb;
RelayKey? _key;

RtdbClient _client() => _rtdb ??= RtdbClient(
  databaseUrl: FirebaseConfig.compiled.databaseUrl,
  idToken: _firebase().idToken,
);

/// Android's relay key: the shared passphrase and the derived key live in
/// the keystore, where crdt_sync_flutter's lock button writes them.
RelayKey? openRelayKey() => _key ??= RelayKey(
  rtdb: _client(),
  readPassphrase: () => kSecureStorage.read(key: kE2ePassphraseKey),
  cache: keystoreKeyCache(relayKeyScope),
);

/// Android: requests to the PC go through Firebase RTDB, sealed.
Assistant openAssistant(Store store) => RelayAssistant(
  rtdb: _client(),
  deviceId: () => deviceId(store),
  session: _firebase(),
  sealer: openRelayKey()!.sealer,
);

// coverage:ignore-end
