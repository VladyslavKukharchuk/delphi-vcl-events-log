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

- **Case-insensitive search beyond ASCII.** SQLite's `LIKE` folds ASCII only, so searching
  `помилка` will not match `Помилка`. Fixing it properly means a lowercased shadow column, a schema
  change and a migration — declined here for text this application never produces
  ([ADR 0010](docs/adr/0010-search-and-severity-filter.md)).
- **Test coverage.** The JSON validation and the generator session are covered; the repository and
  the form are not. The repository would need a test database, the form a UI harness.
- **Sorting by column**, and a filter on a time range. The table is fixed to newest first.
- **Editing an event, or deleting a single one.** Today the only removal is all or nothing.
- **Export back to JSON.** Import is one-way.
- **Remembering the session** — window size, the last filter, the last folder used for import.
- **A portable mode**, keeping the database beside the executable for a copy-and-run install. It was
  considered and rejected as its own decision, not overlooked
  ([ADR 0005](docs/adr/0005-database-file-location.md)).
- **A build and test pipeline.** Impossible in this edition, which is why `make` only runs what the
  IDE has already built.
