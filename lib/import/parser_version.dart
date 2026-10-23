/// Version of the importers' structuring rules. Bump it with EVERY change
/// that can alter a parse (kinds, speakers, line splits, sections): the app
/// re-parses stored scripts whose version is older and moves the user's
/// per-line data to the new line indices (lib/storage/reparse.dart).
/// Scripts stored before versions existed count as 0.
const int parserVersion = 1;
