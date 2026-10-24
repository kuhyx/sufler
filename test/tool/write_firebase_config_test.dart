import 'package:flutter_test/flutter_test.dart';

import '../../tool/write_firebase_config.dart';

const _ignore = 'ignore_for_file: lines_longer_than_80_chars';

void main() {
  // The analyzer flags an ignore that suppresses nothing (unnecessary_ignore),
  // so the 80-column ignore must appear exactly when a line needs it: CI's
  // --placeholder file has none, a real install's client id line does.
  test('placeholder values render without the 80-column ignore', () {
    final out = render(FirebaseLocal.empty);
    expect(out, isNot(contains(_ignore)));
    expect(out.split('\n').where((l) => l.length > 80), isEmpty);
  });

  test('long values render with the 80-column ignore', () {
    final out = render(
      FirebaseLocal(
        apiKey: 'k' * 39,
        databaseUrl:
            'https://example-default-rtdb.europe-west1.firebasedatabase.app',
        syncUid: 'u' * 28,
        serverClientId: '${'1' * 12}-${'a' * 32}.apps.googleusercontent.com',
      ),
    );
    expect(out, contains(_ignore));
  });
}
