import 'package:sufler/model/json.dart';
import 'package:sufler/storage/library.dart';

/// Each library's write chain per script, so a read-modify-write never
/// interleaves (per library: another store's writes do not wait on it).
final _askWrites = Expando<Map<String, Future<void>>>();

final _inFlight = Expando<Map<String, Set<PendingAsk>>>();

/// A "Zapytaj Claude" question not yet answered: the line it is about and
/// the words asked about.
typedef PendingAsk = ({int index, String selection});

/// Offline-first "Zapytaj Claude" questions on a stored script.
///
/// A question asked while the PC is offline is stored under `asks/<scriptId>`
/// (`{"asks": [{"index": int, "selection": String}, ...]}`) the moment it is
/// asked, so an app restart does not drop it; it is dropped — the key with
/// its last entry — once the note is saved or the PC refused it.
extension PendingAsks on ScriptLibrary {
  /// The questions not yet answered for script [id].
  Future<List<PendingAsk>> pendingAsks(String id) async {
    final asks = (await store.readJson('asks/$id'))?['asks'];
    if (asks == null) return const [];
    return objectList(
      asks,
      (a) => (index: a['index']! as int, selection: a['selection']! as String),
    );
  }

  /// Questions of script [id] an `Ask` is sending in this app run (live,
  /// so a stored one is not sent a second time).
  Set<PendingAsk> asksInFlight(String id) =>
      (_inFlight[this] ??= {})[id] ??= {};

  /// Stores [ask] for script [id] (a no-op when already stored), after
  /// every earlier write of this script's questions.
  Future<void> savePendingAsk(String id, PendingAsk ask) => _askWrite(
    id,
    (asks) => asks.any((a) => a == ask) ? asks : [...asks, ask],
  );

  /// Removes [ask] from script [id]; the key goes with its last entry.
  Future<void> dropPendingAsk(String id, PendingAsk ask) =>
      _askWrite(id, (asks) => asks.where((a) => a != ask).toList());

  /// Moves script [id]'s questions to new line indices after a re-parse
  /// ([map]: old index -> new); a question whose line is gone is dropped.
  Future<void> movePendingAsks(String id, Map<int, int> map) => _askWrite(
    id,
    (asks) => [
      for (final a in asks)
        if (map[a.index] case final to?) (index: to, selection: a.selection),
    ],
  );

  /// Runs [change] on script [id]'s stored questions after every earlier
  /// one, so two questions asked at once both survive (an empty result
  /// deletes the key).
  Future<void> _askWrite(
    String id,
    List<PendingAsk> Function(List<PendingAsk>) change,
  ) {
    Future<void> run() async {
      final next = change(await pendingAsks(id));
      if (next.isEmpty) {
        await store.delete('asks/$id');
      } else {
        await store.writeJson('asks/$id', {
          'asks': [
            for (final a in next) {'index': a.index, 'selection': a.selection},
          ],
        });
      }
    }

    final chain = _askWrites[this] ??= {};
    final result = (chain[id] ?? Future<void>.value()).then((_) => run());
    chain[id] = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}
