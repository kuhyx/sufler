/// The legacy `.anki2` collection schema (`col.ver = 11`).
///
/// Deliberately the *legacy* schema, not the modern `anki21b`/zstd format:
/// AnkiDroid still imports ver 11, it needs no compression scheme beyond the
/// zip itself, and it is stable — the newer formats have changed repeatedly.
///
/// `ix_notes_csum` is the reason `notes.csum` must be populated rather than
/// left at genanki's literal 0: it exists so Anki can find duplicate notes by
/// checksum on import.
library;

/// `CREATE TABLE`/`CREATE INDEX` statements for a ver-11 collection.
const String collectionSchema = '''
CREATE TABLE col (
    id              integer primary key,
    crt             integer not null,
    mod             integer not null,
    scm             integer not null,
    ver             integer not null,
    dty             integer not null,
    usn             integer not null,
    ls              integer not null,
    conf            text not null,
    models          text not null,
    decks           text not null,
    dconf           text not null,
    tags            text not null
);
CREATE TABLE notes (
    id              integer primary key,
    guid            text not null,
    mid             integer not null,
    mod             integer not null,
    usn             integer not null,
    tags            text not null,
    flds            text not null,
    sfld            integer not null,
    csum            integer not null,
    flags           integer not null,
    data            text not null
);
CREATE TABLE cards (
    id              integer primary key,
    nid             integer not null,
    did             integer not null,
    ord             integer not null,
    mod             integer not null,
    usn             integer not null,
    type            integer not null,
    queue           integer not null,
    due             integer not null,
    ivl             integer not null,
    factor          integer not null,
    reps            integer not null,
    lapses          integer not null,
    left            integer not null,
    odue            integer not null,
    odid            integer not null,
    flags           integer not null,
    data            text not null
);
CREATE TABLE revlog (
    id              integer primary key,
    cid             integer not null,
    usn             integer not null,
    ease            integer not null,
    ivl             integer not null,
    lastIvl         integer not null,
    factor          integer not null,
    time            integer not null,
    type            integer not null
);
CREATE TABLE graves (
    usn             integer not null,
    oid             integer not null,
    type            integer not null
);
CREATE INDEX ix_notes_usn on notes (usn);
CREATE INDEX ix_cards_usn on cards (usn);
CREATE INDEX ix_revlog_usn on revlog (usn);
CREATE INDEX ix_cards_nid on cards (nid);
CREATE INDEX ix_cards_sched on cards (did, queue, due);
CREATE INDEX ix_revlog_cid on revlog (cid);
CREATE INDEX ix_notes_csum on notes (csum);
''';

/// Schema version written to `col.ver`.
const int ankiSchemaVersion = 11;

/// The note type id, **hardcoded and never regenerated** (and distinct from
/// lyricanki's). Anki keys a note type by this id: a fresh one per export
/// would create "sufler-1", "sufler-2", ... and re-imported notes would never
/// match their predecessors. Deck ids are derived from deck names instead
/// (`stableId`), for the same reason.
const int modelId = 1729700000000;

/// Anki's default deck, which a collection must always carry as deck `"1"`.
const int defaultDeckId = 1;

/// Field names, in the order they are joined into `notes.flds`.
const List<String> fieldNames = <String>['Cue', 'Line'];

/// The separator Anki joins note fields with: ASCII unit separator, `0x1f`.
const String fieldSeparator = '\x1f';
