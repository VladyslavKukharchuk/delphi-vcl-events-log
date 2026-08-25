# 0006. Database schema and value encodings

- **Status:** accepted
- **Date:** 2026-08-21

## Context

ADR 0004 puts the events in SQLite and ADR 0005 puts the file under `%LOCALAPPDATA%`. What remains is
the schema: which columns exist, and how a `TLogEvent` — a UUID, a `TDateTime`, a string and an
enumeration — is written into a database whose columns have no fixed type.

- The schema is visible. Anyone can open the file in a SQLite browser, and a reviewer probably will.
- SQLite is dynamically typed: a declared column type is a preference, not a constraint, so the
  encoding has to be chosen deliberately rather than fallen into.
- Filtering runs as SQL — searching text and restricting by severity happen in a `where` clause, and
  the default view is the most recent rows by time.
- `TDateTime` is a `Double` counting days from 30 December 1899; written raw it is a number no other
  tool can interpret. And Delphi's `GUIDToString` produces a brace-wrapped form that `StringToGUID`
  then insists on.

## Options

### Timestamp encoding

- **`REAL`, the raw `TDateTime`.** Pro: eight bytes, no conversion, comparison works directly. Con:
  unreadable outside Delphi — `order by` works but a human sees `46265.31`.
- **`TEXT`, ISO 8601.** Pro: readable everywhere, and lexicographic ordering equals chronological
  ordering, so `order by time desc` and range predicates need no conversion. Matches the JSON format.
  Con: about twenty bytes instead of eight, and a conversion on every read and write.
- **`INTEGER`, Unix milliseconds.** Pro: compact and orders correctly. Con: still not readable by
  eye, and a second time representation alongside the one the JSON format uses.

### Identifier encoding

- **Brace-wrapped, `{F47AC10B-…}`.** Pro: round-trips with no helper code. Con: a Delphi convention;
  in the JSON file — a deliverable a reviewer reads — it looks wrong.
- **Canonical, `f47ac10b-…`.** Pro: the conventional form everywhere else, so the same text serves
  the database and the JSON file. Con: needs a small pair of helpers.
- **16-byte `BLOB`.** Pro: smallest. Con: invisible in a browser, and no longer copy-pasteable.

Column names were the third question: short forms (`ts`, `txt`) against names matching the model.

## Decision

```sql
create table if not exists events (
  id       text primary key,
  time     text not null,
  text     text not null,
  severity text not null
);
create index if not exists idx_events_time on events(time);
create index if not exists idx_events_severity on events(severity);
```

**Names match the model**, so the mapping needs no explanation; the cost is cosmetic — `text text not
null` reads strangely, and neither name is reserved in SQLite. **`time` is ISO 8601 text**, because
the encoding that is readable is also the one the queries want, and it keeps a single time format
across the database and the JSON file. **`id` is the canonical UUID form**, so the database, the JSON
file and any error message carry exactly the same text. **`severity` stores the names from
`SeverityNames`** — the same constant the JSON parser and the table column use, so the database
cannot drift from either.

Both indexes exist because severity is an equality predicate and time is the default ordering. Event
text is deliberately left unindexed: a `like '%…%'` search cannot use a B-tree index, and pretending
otherwise would be worse than not having one. If text search ever needs to be fast, the answer is
FTS5.

## Consequences

Every read and write converts the timestamp and the identifier, so exactly one unit may own those
conversions — and it is `EventsLog.Event` in `src/Model`, beside `SeverityNames` and the record whose
values they encode. Not `src/Repository`, for the reason the decision above already gives: this text
is not the database's private encoding. The JSON importer parses the same three forms and the table
column displays them, so a pair of helpers in the repository would be a second copy for everyone
else. SQLite will not stop anything from being written into these columns — a `REAL` timestamp
inserted by mistake would be stored happily and sort in a different order from the text rows around
it. The guard is that only one unit converts values, not the column types.
