# Events Log

A VCL desktop application that keeps a log of events: a table of everything recorded, an import of
event history from JSON, search by message text, a filter by severity, and a background generator
that appends one random event a second.

Assignment statement: [docs/Test task Delphi Developer.md](docs/Test%20task%20Delphi%20Developer.md).

## Delphi version

Built with **Embarcadero RAD Studio 37.0, Personal edition** (`bds.exe` file version
37.0.60542.8024). The project targets Win32 and Win64; Win64 is the default platform.

Only the standard RTL/VCL and FireDAC are used — no third-party components or packages. SQLite is
linked statically through `FireDAC.Phys.SQLiteWrapper.Stat`, so the executable runs on its own with
no DLL beside it.

## What it does

- **Events table.** Every event shows all four attributes in its own column: `Id`, `Time`,
  `Severity`, `Text`. Identifiers are UUIDs and are shown in full so they can be copied and compared
  ([ADR 0003](docs/adr/0003-uuid-event-identifiers.md),
  [ADR 0008](docs/adr/0008-listview-for-the-events-table.md)).
- **Import from JSON.** *Import JSON…* opens a file, validates it and shows a preview before
  anything is stored: one tab lists the events that will be imported, another lists every record
  that was rejected and why. A malformed file or a broken record never reaches the store and never
  crashes the application ([ADR 0014](docs/adr/0014-import-problems-window.md),
  [ADR 0015](docs/adr/0015-import-preview-and-confirmation.md)).
- **Search and filter.** The search box matches the event text, the combo box narrows the table to
  one severity. Both are evaluated as SQL, not as a scan in memory
  ([ADR 0010](docs/adr/0010-search-and-severity-filter.md)).
- **Background generation.** *Start generating* runs a generator thread that produces one random
  event every second and hands it to the UI thread; *Stop generating* ends it immediately. The
  window stays responsive throughout ([ADR 0011](docs/adr/0011-event-generator-thread.md)).
- **Paging.** The table shows one page at a time — 50, 100, 200 or 500 rows, newest first — with
  *Previous* / *Next* and a page indicator, so an unbounded log never has to be copied into the view
  ([ADR 0018](docs/adr/0018-paged-events-table.md)).

Two things go beyond the statement and are deliberate additions rather than accidents: events are
kept in a local SQLite database and therefore survive a restart
([ADR 0004](docs/adr/0004-sqlite-for-local-persistence.md)), and *Clear all events* empties that
store, since nothing else in the application removes an event
([ADR 0009](docs/adr/0009-json-import-semantics.md)).

## Program structure

```
EventsLog.dpr            entry point and composition root
src/Model/               entities and filtering - knows about neither VCL nor JSON
  EventsLog.Event.pas      TLogEvent, TEventSeverity, and the text encodings of both
  EventsLog.Filter.pas     TEventFilter: search text plus a set of severities
src/Repository/          data access
  EventsLog.Database.pas       the FireDAC connection and where the database file lives
  EventsLog.Schema.pas         creates the table and its indexes on first run
  EventsLog.EventRepository.pas  IEventRepository: insert, count, read a page, delete all
  EventsLog.EventFile.pas      reads and validates a JSON file into events plus a report
src/Services/            background work
  EventsLog.Generator.pas        the TThread that produces one random event a second
  EventsLog.GeneratorSession.pas owns that thread and stores what it produces
src/UI/                  the form and its wiring
  Main.pas / .dfm            the window; wiring only, no business logic
  EventsLog.Table.pas        the virtual TListView, its paging and its refresh
  EventsLog.FilterBar.pas    the search box and severity combo, read as a TEventFilter
  EventsLog.Actions.pas      import, clear and the generator toggle behind one object
  EventsLog.ImportPreview.pas the modal that shows what an import would store
tests/                   DUnitX project and the sample JSON files
docs/adr/                architecture decision records
```

Dependencies point one way: `src/UI` → `src/Services` → `src/Repository` → `src/Model`. Nothing in
`src/Model` references another layer, and no unit outside `src/UI` uses `Vcl.*` or shows a dialog —
errors travel out as results or exceptions. No `TDataSet` leaves `src/Repository`: a query turns rows
into `TLogEvent` values before returning them.

`EventsLog.dpr` is the composition root. It opens the database, prepares the schema, creates the
repository and hands it to the form as an `IEventRepository`
([ADR 0013](docs/adr/0013-repository-interface-and-composition-root.md)). If that fails, the form
still opens, says why, and disables the controls that would need a database.

Threading is deliberately narrow: the generator builds an event on its own thread and hands it over
with `TThread.Queue`, so the UI thread is the only one that ever touches the database or the array
behind the table ([ADR 0007](docs/adr/0007-event-repository.md)). While the generator runs, a 250 ms
timer coalesces the refreshes rather than repainting per event.

Every decision worth questioning is written down in [docs/adr/](docs/adr/) — the grid control, the
JSON semantics, the threading model, the storage. Start there rather than reverse-engineering the
"why" from the code.

## Building and running

This edition of RAD Studio refuses command-line compiling — both `msbuild` and `dcc64` answer *"This
version of the product does not support command line compiling"* — so building happens in the IDE:

1. Open `EventsLog.dproj`, pick a platform and press **Shift+F9** (Build).
2. The executable lands in `Win64\Debug\EventsLog.exe` (or the matching `Win32` / `Release` folder).

The tests are a separate DUnitX project, `tests/EventsLogTests.dproj`, covering the JSON validation
and the generator session against a fake repository. Build it in the IDE the same way; running it
needs no IDE:

```
make test      run the tests, exit code reports pass or fail
make status    say when the test binary was last built
make clean     delete the build output of both projects
```

`make` deliberately has no build target, for the reason above — and for the same reason there is no
CI pipeline.

## Data

### The JSON file

An array of objects with three string fields. `tests/sample-events.json` is the test data file:

```json
[
  { "time": "2026-08-19T08:14:02.000", "text": "Application started", "severity": "Info" },
  { "time": "2026-08-19T09:02:47.880", "text": "Disk space on volume C is below 15 per cent", "severity": "Warning" }
]
```

- `time` is ISO 8601 (`2026-08-19T08:14:02.000`). A trailing `Z` or an explicit offset is honoured
  and converted to local time ([ADR 0006](docs/adr/0006-database-schema-and-encodings.md)).
- `severity` is `Info`, `Warning` or `Error`, compared without regard to case. An unknown value makes
  the record invalid — it is skipped and reported, never silently turned into `Info`.
- Identifiers are minted on import, so an `id` key in the file is ignored. Importing the same file
  twice therefore stores its events twice.
- An import **appends**. The store is a log that grows from two directions, the generator over time
  and each import, so replacing would discard what the generator recorded
  ([ADR 0009](docs/adr/0009-json-import-semantics.md)). Use *Clear all events* to start empty.

Two more files sit beside it as fixtures for the tests and as something to try by hand:
`sample-events-invalid.json`, valid JSON whose records are broken one way each, and
`sample-events-malformed.json`, which is not JSON at all. Importing either shows what the application
does with bad input instead of describing it.

### Where the events are stored

`%LOCALAPPDATA%\EventsLog\events.db` — a SQLite database created on first run
([ADR 0005](docs/adr/0005-database-file-location.md)). **Deleting that folder resets the application
to empty.** The path is per user, so two accounts on one machine keep separate logs, and copying the
executable elsewhere does not bring the data along.

## What could be improved with more time

Ordered within each group by how much it would matter, most significant first. Several of these
revise a decision rather than extend it; where that is so, the ADR to supersede is named.

### Carrying millions of events

The application is sized for the load the statement describes, one event a second. The items below
are where it would stop being comfortable long before it stopped working. Everything that touches the
schema needs `PRAGMA user_version` and a migration step first, which the schema does not have yet.

1. **Keep `count(*)` off the hot path.** The table counts the whole filtered set on every refresh —
   on each keystroke in the search box, and four times a second while the generator runs. Together
   with a `LIKE` scan that is a full table scan several times a second, and it is the first thing
   that would freeze the window on a large log. Counting with a cap
   (`select count(*) from (select 1 … limit 10001)`, shown as "10,000+") is the cheap fix; paging by
   key removes the need for a total altogether.
2. **Index the text search with FTS5.** `text like '%…%'` can never use an index, so every search is
   a second full scan. An FTS5 shadow table with the trigram tokenizer turns "contains" into an
   indexed lookup and, as a side effect, removes the ASCII-only case folding recorded in
   [ADR 0010](docs/adr/0010-search-and-severity-filter.md) — `помилка` would finally match
   `Помилка`. The cost is a set of triggers and roughly half again the database size.
3. **Page by key instead of by offset.** `offset` makes SQLite walk past every row it skips, so page
   500 costs five hundred times page 1. A `where (time, id) < (:lastTime, :lastId)` predicate makes
   every page cost the same. The trade is real and revises
   [ADR 0018](docs/adr/0018-paged-events-table.md): no jumping to page 137, only newer/older plus a
   jump by time.
4. **Encode the columns for the index, and mint UUIDv7.** `time` is 23 bytes of ISO text, `severity`
   a whole word, `id` a 36-character UUID as the primary key. Size is the smaller problem; locality
   is the larger one, because a random v4 identifier lands on a random B-tree page at every insert.
   Integer time, integer severity and a 16-byte blob id would shrink the indexes, and UUIDv7 — being
   time-ordered — would let the index append again while keeping the "nobody coordinates" property
   that won [ADR 0003](docs/adr/0003-uuid-event-identifiers.md).
5. **One composite index in place of two thin ones.** An index over three distinct severities buys
   little, and every query has the same shape: filter, then `order by time desc`. A composite
   `(severity, time desc)` — or partial indexes on Warning and Error — serves that shape directly,
   with `ANALYZE` so the planner has statistics to choose it.

Also on the list: ArrayDML for bulk import, a writer thread with its own connection once the event
rate outgrows what [ADR 0007](docs/adr/0007-event-repository.md) assumes, and a retention policy so
the file does not grow without end.

### Development and observability

1. **Make the database path a parameter.** `TDatabase` resolves its own location, and that single
   detail is why the whole data-access layer is untested: there is no way to point it at a temporary
   file. A constructor taking a file name, defaulting to today's path, opens the repository to tests
   against an in-memory database.
2. **Give the application a log of its own.** An events log that records nothing about itself is a
   poor witness. A file under `%LOCALAPPDATA%\EventsLog\log\` holding the startup facts — database
   path, schema version, SQLite version — plus every query slower than a threshold and every
   exception, together with an `Application.OnException` handler, would mean a problem in the field
   leaves a trace instead of a dialog nobody wrote down.
3. **Settle the build question.** There is no CI because this edition refuses command-line
   compiling. Either a licence tier that unlocks `dcc32`/`dcc64`, or a self-hosted runner on a
   machine with the IDE, or a deliberate no — and in that last case, automating everything that does
   not need a compiler: broken Markdown links, duplicate ADR numbers, IDE noise in `.dproj`, and the
   check that every new unit under `src/` is registered in the `.dpr`.
4. **A diagnostics window and a seed command.** Database path and size, journal mode, schema
   version, the timing of recent queries, generator state, and a row count on demand rather than on
   every refresh. Beside it, "seed N events" — without which neither a report about behaviour at
   volume nor any measurement of the items above can be reproduced.
5. **SQL tracing behind a switch.** FireDAC already ships `TFDMoniFlatFileClientLink`; a `-trace`
   flag would log every statement with its timing, at no cost in dependencies. For a design that
   puts all filtering in SQL, that is the instrument that matches it.

Also on the list: lifting the paging arithmetic out of `TEventTable` into a plain object, so the
off-by-one cases can be tested without a VCL control in the room.

### Usability

1. **Colour the row by severity.** Red for Error, amber for Warning. All three levels look alike
   today, so an error sinks into the Info around it. This is the cheapest change here and the one
   most felt: the log becomes something scanned rather than read.
2. **Debounce the search, and show when a query is slow.** Every keystroke queries the database
   immediately. Waiting 250–300 ms after the last one is a handful of lines and the largest single
   improvement in how quick the window feels, before any SQL is touched. A busy indicator past
   ~200 ms would stop a working query from looking like a frozen table.
3. **More than one severity at a time.** The combo offers *All* or exactly one level, while the
   question people actually ask is "Warning and Error, without Info". The model already carries a
   set of severities; only the control is narrower.
4. **An event card and clipboard support.** Long messages are cut off by the column and cannot be
   read in full. A read-only card on double click, Ctrl+C over the selected rows, Ctrl+F into the
   search box and Esc to clear it are the basics for a tool whose output ends up pasted into a
   ticket.
5. **A filter on a time range** — the last hour, today, or a chosen span. For a log this is a more
   natural cut than text search, and unlike text search it rests on an index, so it stays fast at
   any size.

Also on the list: a follow mode that scrolls with new events and pauses when the reader scrolls up
(a toggle, rather than the forced scrolling declined in
[ADR 0011](docs/adr/0011-event-generator-thread.md)); export of the current view back to JSON or CSV;
remembered window size, column widths and last filter; editing or deleting a single event rather than
all of them; sorting by column; and a portable mode, considered and declined in
[ADR 0005](docs/adr/0005-database-file-location.md).
