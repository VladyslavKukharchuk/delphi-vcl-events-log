# 0006. Database schema and value encodings

- **Status:** accepted
- **Date:** 2026-08-21

## Context

ADR 0004 puts the events in SQLite and ADR 0005 puts the file under `%LOCALAPPDATA%`. What remains is
the schema: which columns exist and how a `TLogEvent` — a UUID, a `TDateTime`, a string and an
enumeration — is written into a database whose columns have no fixed type.

Forces at play:

- The schema is visible. Anyone can open the file in a SQLite browser, and a reviewer probably will.
  Column names and stored values are read by people, not only by our code.
- SQLite is dynamically typed. A declared column type is a *preference*, not a constraint, so nothing
  stops any encoding from being stored — which means the encoding has to be chosen deliberately
  rather than fallen into.
- Filtering runs as SQL (decision D8, option B): searching event text and restricting by severity
  happen in a `where` clause, and the default view is the most recent rows by time. Whatever
  encodings are chosen have to support those predicates.
- `TDateTime` is a `Double` counting days from 30 December 1899. Written raw, it is a number no other
  tool can interpret.
- ADR 0003 made the identifier a `TGUID`. Delphi's `GUIDToString` and `TGUID.ToString` both produce a
  brace-wrapped form, `{F47AC10B-...}`, and `StringToGUID` requires those braces.

## Options

Three questions, each with its own alternatives.

### Column names

- **Short forms — `ts`, `txt`.** Pro: compact. Con: abbreviations a reader has to decode, in a file
  read by people.
- **Names matching the model — `time`, `text`, `severity`, `id`.** Pro: each column reads as the
  thing it holds, and lines up with the properties of `TLogEvent`. Con: `text` and `time` are also
  SQL type names, so `text text not null` looks odd, and in a stricter engine they would need
  quoting. In SQLite neither is a reserved keyword, so both are legal identifiers.

### Timestamp encoding

- **`REAL`, the raw `TDateTime`.** Pro: eight bytes, no conversion, and comparison works directly.
  Con: unreadable outside Delphi, because of the 1899 epoch; `order by` works but a human sees
  `46265.31`.
- **`TEXT`, ISO 8601.** Pro: readable everywhere, and lexicographic ordering equals chronological
  ordering, so `order by time desc` and range predicates work without conversion. Matches decision
  D3, which already chose ISO 8601 for the JSON format. Con: about twenty bytes instead of eight, and
  a conversion on every read and write.
- **`INTEGER`, Unix milliseconds.** Pro: compact, orders correctly, understood by other tools. Con:
  still not readable by eye, and introduces a second time representation alongside the one the JSON
  format uses.

### Identifier encoding

- **Brace-wrapped, `{F47AC10B-...}`.** Pro: round-trips through `GUIDToString` and `StringToGUID`
  with no helper code. Con: the braces are a Delphi convention. In the JSON file — a deliverable a
  reviewer reads — they look wrong, and no other tool writes UUIDs that way.
- **Canonical, `f47ac10b-...`.** Pro: the conventional form everywhere outside Delphi, so the same
  text serves the database and the JSON file. Con: needs a small pair of helpers, because
  `StringToGUID` rejects it.
- **16-byte `BLOB`.** Pro: smallest. Con: invisible in a browser, and the identifier stops being
  something you can copy out of the table and paste into a query.

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

- **Names match the model.** `time`, `text`, `severity`, `id` — the same words as the properties of
  `TLogEvent`, so the mapping needs no explanation. The cost is cosmetic: `text text not null` reads
  strangely, and neither name is reserved in SQLite.
- **`time` is ISO 8601 text.** Chosen because ordering and range predicates work on the string
  directly, so the encoding that is readable is also the one the queries want. It also keeps a single
  time format across the database and the JSON file rather than two.
- **`id` is the canonical UUID form, without braces.** The database and the JSON file then carry
  exactly the same text, and that text is what every other tool produces. The price is a helper pair
  next to `TLogEvent`, since `StringToGUID` insists on braces.
- **`severity` stores the names from `SeverityNames`** — the same constant array the JSON parser and
  the table column already use, so the database cannot drift from either.

Both indexes exist because of D8: severity is an equality predicate and time is the default ordering.
Event text is deliberately left unindexed — a `like '%...%'` search cannot use a B-tree index, and
pretending otherwise with an index that never gets used would be worse than not having one. If text
search ever needs to be fast, the answer is FTS5, not an index on this column.

## Consequences

Easier: reading the database by hand; writing a query against it; explaining the format. The same ISO
timestamp and the same UUID text appear in the database, in the JSON file and in any error message,
so there is one representation to learn rather than three.

Harder: every read and write converts the timestamp and the identifier, so those conversions belong
in one place in `src/Repository` and nowhere else. And the schema is created by hand-written SQL
guarded by `if not exists`, because Delphi has no migration tooling — a future column means writing
the `alter table` and deciding what happens to existing files.

To revisit if the assumptions change: text search becoming slow enough to need FTS5, or a volume of
rows where twenty bytes per timestamp against eight actually matters. Either would be a new ADR.

The consequence to watch: SQLite will not stop anything from being written into these columns. A
`REAL` timestamp inserted by mistake would be stored happily and sort in a different order from the
text rows around it. The guard is that only one unit converts values, not the column types.
