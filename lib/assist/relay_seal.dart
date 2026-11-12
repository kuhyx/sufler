/// End-to-end sealing of what the relay carries (DOCS-relay.md "E2E").
///
/// A request and a result are each one *unit*: the fields that hold text
/// (`payload`; `text`, `audioB64`, `error`) go into one `_e2e` blob,
/// crdt_sync's [E2eCipher] bound to the record's path (`sufler/requests/{rid}`,
/// `sufler/results/{rid}`), under the Argon2id key of the shared crdt-sync
/// passphrase. Ids, `kind`, `deviceId`, `ok` and the server times stay clear,
/// as do presence and clients. No new prefix and no copy: the data lives
/// seconds. A record without `_e2e` is read as stored (an older build).
///
/// The twin of `tts/sufler_tts/relay/e2e.py`;
/// `test/assist/relay_e2e_vectors.json` pins both.
library;

import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart'
    show
        E2eCipher,
        E2eHeaderError,
        E2eKey,
        E2eKeyCache,
        E2eReady,
        E2eWrongPassphraseError,
        RemoteStore,
        RemoteSyncError,
        openE2e,
        unlockE2e;
import 'package:flutter/foundation.dart';
import 'package:sufler/assist/rtdb_client.dart';

/// The key a sealed record keeps its blob under.
const String sealedKey = '_e2e';

/// The header (salt, Argon2id cost, check MAC; never a key) the PC writes.
const String relayHeaderPath = 'sufler/e2e';

/// Key-cache and passphrase scope of the relay (one per app).
const String relayKeyScope = 'sufler';

const Set<String> _requestClear = {'kind', 'deviceId', 'ts'};
const Set<String> _resultClear = {'ok', 'at'};

/// Seals and opens relay records with one key.
class RelaySealer {
  /// Creates the sealer.
  const new(this.cipher);

  /// The key's cipher.
  final E2eCipher cipher;

  /// [record] as stored at [path]: everything but [clear] in one blob.
  Future<Map<String, Object?>> _seal(
    String path,
    Map<String, Object?> record,
    Set<String> clear,
  ) async {
    final secret = {
      for (final e in record.entries)
        if (!clear.contains(e.key)) e.key: e.value,
    };
    return {
      for (final e in record.entries)
        if (clear.contains(e.key)) e.key: e.value,
      sealedKey: await cipher.seal(jsonEncode(secret), path: path),
    };
  }

  /// [record] (`{kind, payload, deviceId, ts}`) as written to [path].
  Future<Map<String, Object?>> sealRequest(
    String path,
    Map<String, Object?> record,
  ) => _seal(path, record, _requestClear);

  /// [record] (`{ok, text | audioB64 | error, at}`) as written to [path].
  Future<Map<String, Object?>> sealResult(
    String path,
    Map<String, Object?> record,
  ) => _seal(path, record, _resultClear);

  /// [stored] read at [path] with its blob opened; an unsealed record is
  /// returned as stored. Throws [FormatException] (an `E2eDecryptError`
  /// is one) when the blob does not open: tampered, moved or another key.
  Future<Map<String, Object?>> open(
    String path,
    Map<String, Object?> stored,
  ) async {
    final blob = stored[sealedKey];
    if (blob is! String) return stored;
    final secret = jsonDecode(await cipher.open(blob, path: path));
    if (secret is! Map) throw const FormatException('sealed record not a map');
    return {
      for (final e in stored.entries)
        if (e.key != sealedKey) e.key: e.value,
      ...secret.cast<String, Object?>(),
    };
  }
}

/// The phone's relay key: from the keystore cache, else the shared
/// passphrase and the header the PC wrote. Null means locked: no
/// passphrase, a wrong one, a bad header, or no header yet (the PC creates
/// it; the phone never does, and tries again on the next request).
class RelayKey {
  /// Creates the gate over [rtdb].
  new({required this.rtdb, required this.readPassphrase, required this.cache});

  /// The relay's REST client.
  final RtdbClient rtdb;

  /// The shared crdt-sync passphrase (keystore), null when never entered.
  final Future<String?> Function() readPassphrase;

  /// Where the derived key is kept, so Argon2id runs once per device.
  final E2eKeyCache cache;

  RelaySealer? _sealer;

  /// False only once the key opened (the lock icon): no key, no network
  /// on the first try, or a locked answer all show the closed lock.
  final ValueNotifier<bool> locked = ValueNotifier(true);

  /// The sealer once unlocked; null while locked (never cached as locked,
  /// so the next request tries again). [RtdbError] propagates: no network
  /// is not a lock.
  Future<RelaySealer?> sealer() async {
    if (_sealer case final s?) return s;
    final key = await _unlock();
    locked.value = key == null;
    if (key == null) return null;
    return _sealer = RelaySealer(key.cipher());
  }

  /// Drops the in-memory key and tries again (a new passphrase was saved).
  Future<RelaySealer?> retry() {
    _sealer = null;
    return sealer();
  }

  Future<E2eKey?> _unlock() async {
    final store = RelayHeaderStore(rtdb);
    final cached = await cache.read();
    if (cached != null && cached.length == 32) {
      final state = await openE2e(
        store: store,
        pathPrefix: relayKeyScope,
        key: await E2eKey.fromBytes(cached),
        e2ePath: relayHeaderPath,
      );
      if (state is E2eReady) return state.store.key;
    }
    final passphrase = await readPassphrase();
    if (passphrase == null || passphrase.isEmpty) return null;
    // No header yet: the PC has not run with e2e. Locked, never created here.
    if (await store.getFileText(relayHeaderPath) == null) return null;
    try {
      final key = await unlockE2e(
        store: store,
        pathPrefix: relayKeyScope,
        passphrase: passphrase,
        e2ePath: relayHeaderPath,
      );
      await cache.write(key.bytes);
      return key;
    } on E2eWrongPassphraseError {
      return null;
    } on E2eHeaderError {
      return null;
    } on RemoteSyncError {
      return null; // the header vanished between the reads: not ours to make
    }
  }
}

/// Just enough of crdt_sync's [RemoteStore] to read the header (one JSON
/// string leaf, as the PC writes it). Writing is refused: only the PC
/// creates the header.
class RelayHeaderStore implements RemoteStore {
  /// Creates the store over [_rtdb].
  new(this._rtdb);

  final RtdbClient _rtdb;

  @override
  Future<String?> getFileText(String path) async {
    final value = await _rtdb.get(path);
    if (value == null || value is String) return value as String?;
    // Not a header the PC wrote: unlock reports a bad header.
    return jsonEncode(value);
  }

  @override
  Future<void> putFileText(
    String path,
    String text, {
    required String message,
  }) => throw RemoteSyncError('only the PC creates the relay e2e header');

  @override
  Future<List<String>> listDirectory(String path) async => const [];

  @override
  Future<void> deleteFile(String path, {String message = ''}) =>
      throw RemoteSyncError('the relay never deletes the e2e header');

  @override
  Future<bool> canAccessRemote() async => true;

  @override
  void close() {}
}
