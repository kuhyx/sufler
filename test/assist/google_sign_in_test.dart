import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_account_token/google_account_token.dart'
    show kGoogleAccountTokenChannel;
import 'package:sufler/assist/google_sign_in.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      kGoogleAccountTokenChannel,
      null,
    );
  });

  test('no token off Android, so desktop never signs in', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(await googleIdToken('web-client-id'), isNull);
  });

  test('empty client id gives no token', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await googleIdToken(''), isNull);
  });

  test('Android returns the plugin token for the Web client id', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    MethodCall? seen;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      kGoogleAccountTokenChannel,
      (call) async {
        seen = call;
        return 'id-token';
      },
    );
    expect(await googleIdToken('web-client-id'), 'id-token');
    expect(seen?.method, 'idToken');
    expect((seen?.arguments as Map)['serverClientId'], 'web-client-id');
  });
}
