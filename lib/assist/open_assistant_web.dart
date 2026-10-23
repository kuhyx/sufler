import 'package:http/http.dart' as http;
import 'package:sufler/assist/assistant.dart';
import 'package:sufler/assist/http_assistant.dart';
import 'package:sufler/assist/pc_session.dart';
import 'package:sufler/storage/store.dart';

/// Desktop: the wrapper on this PC forwards straight to the voice service.
// coverage:ignore-start
Assistant openAssistant(Store store) =>
    HttpAssistant(client: http.Client(), base: Uri.base);

/// Desktop needs no sign-in: the PC is right here.
PcSession? openPcSession() => null;
// coverage:ignore-end
