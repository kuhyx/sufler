/// Finding and launching the Chrome `--app` window the desktop app runs in.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// The wrapper's port. Must stay fixed: the browser keys IndexedDB and
/// localStorage (the imported scripts, rehearsal prefs, audio packs) by
/// origin, so a different port looks like a different app with no data.
/// 8791 is the voice service; 8792 is the next free one.
const kWrapperPort = 8792;

/// The app origin. `127.0.0.1`, never `localhost`: that is a different origin
/// with its own (empty) storage, and the wrapper binds IPv4 loopback only.
const kAppOrigin = 'http://127.0.0.1:$kWrapperPort';

/// Browser profile directory. Must stay stable for the same reason as
/// [kWrapperPort]: the app's data lives inside it.
String profileDir(String home) =>
    p.join(home, '.local', 'share', 'sufler', 'chrome-profile');

/// Returns the first Chrome-family browser on this machine, or ''.
///
/// [override] defaults to `$SUFLER_BROWSER`; [exists] to a file check.
String findBrowser({String? override, bool Function(String path)? exists}) {
  // Deliberately broad: this machine runs Thorium behind /opt/google/chrome
  // and has a policy that uninstalls `chromium`, so no single browser can be
  // assumed (and none is a package dependency).
  final candidates = [
    override ?? Platform.environment['SUFLER_BROWSER'] ?? '',
    '/opt/google/chrome/chrome',
    '/opt/thorium-browser/thorium-browser',
    '/usr/bin/google-chrome-stable',
    '/usr/bin/chromium',
    '/usr/bin/brave',
  ];
  final check = exists ?? (String path) => File(path).existsSync();
  return candidates.firstWhere(
    (path) => path.isNotEmpty && check(path),
    orElse: () => '',
  );
}

/// Command-line arguments for the app window.
List<String> browserArgs(String home) => [
  '--app=$kAppOrigin',
  '--user-data-dir=${profileDir(home)}',
  // Sets WM_CLASS to match the .desktop StartupWMClass; otherwise the
  // taskbar shows the browser's icon instead of sufler's.
  '--class=sufler',
  '--no-first-run',
  // Keep Chrome off the GNOME keyring: a locked keyring blocks page loads
  // behind an unlock prompt. Nothing here needs OS-level encryption.
  '--password-store=basic',
];

/// Starts a process; [Process.start] in production.
typedef ProcessStarter =
    Future<Process> Function(String executable, List<String> args);

/// Launches the app window and waits for the browser process to exit.
///
/// Returns true when it ran long enough (> 5 s) to have owned the window.
/// Chrome exits at once when it hands the URL to an instance that already
/// owns the profile (or finds a stale SingletonLock); the caller must then
/// keep serving rather than pull the server out from under that window.
Future<bool> launchBrowser(
  String home, {
  String? browser,
  ProcessStarter? start,
  DateTime Function()? clock,
}) async {
  final exe = browser ?? findBrowser();
  if (exe.isEmpty) {
    stderr.writeln('No Chrome-family browser found; open $kAppOrigin.');
    return false;
  }
  final now = clock ?? DateTime.now;
  final started = now();
  final process = await (start ?? Process.start)(exe, browserArgs(home));
  await process.exitCode;
  return now().difference(started) > const Duration(seconds: 5);
}
