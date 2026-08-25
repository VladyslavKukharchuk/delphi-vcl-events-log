# Events Log

A VCL desktop application that keeps a log of events: a table of everything recorded, an import of
event history from JSON, search by message text, a filter by severity, and a background generator
that appends one random event a second.

Assignment statement: [docs/Test task Delphi Developer.md](docs/Test%20task%20Delphi%20Developer.md).

![The generator filling the table, then the search box, then the severity filter](docs/media/demo.gif)

## Download

Ready-made builds are attached to the
[v1.0.0 release](https://github.com/VladyslavKukharchuk/delphi-vcl-events-log/releases/tag/v1.0.0):
`EventsLog-1.0.0-win64.zip` and `EventsLog-1.0.0-win32.zip`. Each holds one executable that needs
nothing beside it — SQLite is linked statically
([ADR 0004](docs/adr/0004-sqlite-for-local-persistence.md)) — plus `sample-events.json` to import.

Building from source is under [Building and running](#building-and-running).

## Delphi version

Built with **Delphi 13 (RAD Studio 13), Community Edition** — compiler version 37.0, `bds.exe` file
version 37.0.60542.8024.

Only the standard RTL/VCL and FireDAC are used — no third-party components or packages.

## What it does

- **Events table.** Every event shows all four attributes in its own column: `Id`, `Time`,
  `Severity`, `Text`. Identifiers are UUIDs and are shown in full so they can be copied and compared
  ([ADR 0003](docs/adr/0003-uuid-event-identifiers.md),
  [ADR 0008](docs/adr/0008-listview-for-the-events-table.md)).
- **Import from JSON.** *Import JSON…* opens a file, validates it and shows a preview before
  anything is stored: one tab lists the events that will be imported, another lists every record
  that was rejected and why. A malformed file or a broken record never reaches the store and never
  crashes the application ([ADR 0009](docs/adr/0009-json-import-semantics.md),
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

Every decision worth questioning is written down as an ADR. [docs/adr/](docs/adr/) opens with an
index of all fifteen, grouped by what they decide, so you can pick the ones you want to argue with
rather than read them in order.

## Building and running

This edition of RAD Studio refuses command-line compiling — so building happens in the IDE:

1. Open `EventsLog.dproj`, pick a platform and a build configuration, then press **Shift+F9** (Build).
2. The executable lands in `Win64\Release\EventsLog.exe` (or the matching `Win32` / `Debug` folder).

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

![The DUnitX runner: 27 tests found, 27 passed, none failed](docs/media/tests-passing.jpg)

## Data

### The JSON file

An array of objects with three string fields. `tests/sample-events.json` is the test data file:

```json
[
  { "time": "2026-08-19T08:14:02.000", "text": "Application started", "severity": "Info" },
  { "time": "2026-08-19T09:02:47.880", "text": "Disk space on volume C is below 15 per cent", "severity": "Warning" }
]
```

`time` is ISO 8601, and a trailing `Z` or an explicit offset is honoured and converted to local time;
`severity` is `Info`, `Warning` or `Error` compared without regard to case, and an unknown value makes
the record invalid — skipped and reported, never silently turned into `Info`. Identifiers are minted
on import, so an `id` key in the file is ignored and importing the same file twice stores its events
twice. An import **appends** rather than replaces, since the generator writes to the same log
([ADR 0009](docs/adr/0009-json-import-semantics.md)); *Clear all events* is what starts it empty.

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

1. **Recognise an import that has already been done.** Opening the same file twice stores its events
   twice, because identifiers are minted as the file is read rather than taken from it. A content
   key — `(time, text, severity)` behind a unique index, with `insert or ignore` — changes no file
   format, but it collapses two distinct events sharing a millisecond, a message and a level, which
   is what a pair of workers emitting the same line does. That guess about identity is avoidable:
   what a user calls "already imported" is a file, not an event, so recording which import produced
   which events would let the import preview say so and let them choose.
2. **A filter on a time range** — the last hour, today, or a chosen span. For a log this is a more
   natural cut than text search, and unlike text search it rests on `idx_events_time`, which already
   exists, so it stays fast at any size.
3. **Keep `count(*)` off the hot path.** The table counts the whole filtered set on every refresh —
   on each keystroke in the search box, and once per generated event — up to four times a second —
   while the generator runs, and on a large log it is the first thing that would freeze the window.
   Counting with a cap (`select count(*) from (select 1 … limit 10001)`, shown as "10,000+") is the
   cheap fix. Paging by key rather than by `offset` — which makes SQLite walk past every row it
   skips — removes the need for a total altogether, and costs the page numbers with it: no jumping
   to page 137, only newer and older.
4. **Fold case beyond ASCII.** SQLite is linked statically, without ICU, so `LIKE` folds case for
   ASCII letters and for nothing else: `помилка` does not match `Помилка`. That is the price of
   shipping one executable with no DLL beside it, not an oversight. An FTS5 shadow table with the
   trigram tokenizer fixes the folding and, as a side effect, turns `text like '%…%'` — which can
   never use an index — into an indexed lookup. The cost is a set of triggers and roughly half again
   the database size.
5. **Colour the row by severity.** Red for Error, amber for Warning. All three levels look alike
   today, so an error sinks into the Info around it, and the log is something read rather than
   scanned.
6. **Give the application a log of its own.** An events log that records nothing about itself is a
   poor witness. A file under `%LOCALAPPDATA%\EventsLog\log\` holding the startup facts — database
   path, schema version, SQLite version — plus every query slower than a threshold and every
   exception, together with an `Application.OnException` handler, would mean a problem in the field
   leaves a trace instead of a dialog nobody wrote down.
