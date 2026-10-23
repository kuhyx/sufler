import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:sufler/assist/device_id.dart';
import 'package:sufler/storage/idb_store.dart';

void main() {
  test('a per-install uuid4, minted once and kept', () async {
    final store = IdbStore(idbFactoryMemory, dbName: 'device-id');
    final first = await deviceId(store);
    expect(
      first,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}'
          r'-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(await deviceId(store), first);
    expect(await store.readJson(deviceIdKey), {'id': first});
    final other = IdbStore(idbFactoryMemory, dbName: 'device-id-2');
    expect(await deviceId(other), isNot(first));
  });
}
