/// This install's persisted uuid4: who sent a relay request.
library;

import 'dart:math';

import 'package:sufler/storage/store.dart';

/// Where the id lives in the app's [Store].
const deviceIdKey = 'device/id';

/// The install's uuid4, minted on first use and kept in [store] (never a
/// fixed "phone" constant: two phones must not look like one).
Future<String> deviceId(Store store) async {
  final kept = (await store.readJson(deviceIdKey))?['id'];
  if (kept is String && kept.isNotEmpty) return kept;
  final id = _uuid4();
  await store.writeJson(deviceIdKey, {'id': id});
  return id;
}

String _uuid4() {
  final random = Random.secure();
  final b = [for (var i = 0; i < 16; i++) random.nextInt(256)];
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
