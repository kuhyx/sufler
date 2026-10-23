// coverage:ignore-file
// Entry point for the desktop wrapper: resolves paths, starts the server and
// launches the browser. Serving logic lives in lib/desktop (covered by
// test/desktop); keep this file thin wiring.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sufler/desktop/browser_launcher.dart';
import 'package:sufler/desktop/wrapper_server.dart';

/// `errno` for EADDRINUSE on Linux (the wrapper is Linux-only).
const _addressInUse = 98;

Future<void> main(List<String> args) async {
  final home = Platform.environment['HOME'];
  if (home == null) {
    stderr.writeln('HOME is not set.');
    exit(1);
  }
  // `dart build cli` emits bundle/bin/<exe> beside bundle/lib/; the package
  // installs web assets one level up (/opt/sufler/web). --web-root overrides
  // for development runs out of the repo.
  final webRoot =
      _argValue(args, '--web-root') ??
      p.normalize(p.join(p.dirname(Platform.resolvedExecutable), '..', 'web'));
  if (!Directory(webRoot).existsSync()) {
    stderr.writeln('web assets not found at $webRoot');
    exit(1);
  }

  final server = WrapperServer(webRoot: webRoot);
  try {
    await server.start(kWrapperPort);
  } on SocketException catch (e) {
    if (e.osError?.errorCode != _addressInUse) {
      stderr.writeln('could not serve on $kAppOrigin: ${e.osError?.message}');
      exit(1);
    }
    // The port cannot move (the app's data is keyed by origin), so either a
    // sufler wrapper already owns it -- open another window onto it -- or
    // something else does, and we refuse.
    if (!await _isSufler()) {
      stderr.writeln('port $kWrapperPort is taken by another program.');
      exit(1);
    }
    stdout.writeln('sufler is already running; opening a window.');
    if (!args.contains('--no-browser')) await launchBrowser(home);
    return;
  }
  stdout.writeln('sufler desktop serving on $kAppOrigin');

  if (args.contains('--no-browser')) return;
  if (!await launchBrowser(home)) {
    // Handoff to an existing window (or no browser): keep serving.
    stdout.writeln('Browser returned at once; still serving. Ctrl-C to stop.');
    return;
  }
  // The browser owned the session and its window closed.
  await server.stop();
}

Future<bool> _isSufler() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final response = await (await client.getUrl(
      Uri.parse('$kAppOrigin/api/health'),
    )).close();
    final body = await utf8.decodeStream(response);
    return body.contains('"sufler"');
  } on Object {
    return false;
  } finally {
    client.close(force: true);
  }
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}
