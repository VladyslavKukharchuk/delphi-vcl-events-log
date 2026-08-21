# Events Log

A VCL desktop application that keeps a log of events. Every event carries an identifier, a timestamp,
a message and a severity level of Info, Warning or Error. The window shows them in a table, newest
first; history can be imported from a JSON file, searched by message text and filtered by severity;
and a generator can be switched on to append one random event a second from a background thread.

Written as a test assignment — the statement is
[docs/Test task Delphi Developer.docx](docs/Test%20task%20Delphi%20Developer.docx), and it is the
source of truth for scope.

## Delphi version and dependencies

- **RAD Studio / Delphi 37.0**, Personal edition
  (`C:\Program Files (x86)\Embarcadero\Studio\37.0`). The project file carries
  `ProjectVersion 20.3` and `FrameworkType VCL`.
- Platforms **Win32** and **Win64**; Win64 is the default.
- Standard RTL and VCL plus **FireDAC** for data access. **No third-party components or packages.**
- **SQLite** is linked statically through `FireDAC.Phys.SQLiteWrapper.Stat`, so the executable ships
  with no DLL beside it.

## Building and running

This edition refuses command-line compiling — both `msbuild` and `dcc64` answer *"This version of the
product does not support command line compiling"* — so building happens in the IDE:

1. Open `EventsLog.dproj`.
2. **Project → Build EventsLog** (`Shift+F9`).
3. **Run → Run Without Debugging** (`Shift+Ctrl+F9`).

The unit tests are a separate DUnitX project, `tests/EventsLogTests.dproj`, built the same way.
Running them needs no IDE: `make test` executes the built binary and its exit code reports pass or
fail; `make help` lists the rest. There is deliberately no build target and therefore no CI path, for
the reason above.

## Where the data lives

Events are stored in a local SQLite database:

```
%LOCALAPPDATA%\EventsLog\events.db
```

The folder is created on first run. **Deleting `%LOCALAPPDATA%\EventsLog` resets the application to
empty** — that is the reset switch, since nothing inside the application removes events except *Clear
all events*, which removes all of them at once. The `events.db-wal` and `events.db-shm` files beside
it are SQLite's write-ahead log; they belong to the database and go with it.

Persistence is not asked for by the statement. It was added deliberately, and
[ADR 0004](docs/adr/0004-sqlite-for-local-persistence.md) and
[ADR 0005](docs/adr/0005-database-file-location.md) record why.

## Program structure

```
EventsLog.dpr           entry point and composition root
src/Model/              entities and criteria - knows about neither VCL nor JSON
  EventsLog.Event.pas     TLogEvent, the severity enumeration, the text encodings
  EventsLog.Filter.pas    TEventFilter: what the user asked to see, as a value
src/Repository/         data access
  EventsLog.Database.pas        the connection and the schema
  EventsLog.EventRepository.pas the only place that speaks SQL
  EventsLog.Json.pas            JSON import, guarded field by field
src/Services/           background work
  EventsLog.Generator.pas TEventGenerator, a TThread that produces events
src/UI/                 the form and its wiring
  Main.pas / Main.dfm
tests/                  DUnitX project and the sample JSON files
docs/adr/               architecture decision records
```

Dependencies point one way: `src/UI` → `src/Services` → `src/Repository` → `src/Model`. Nothing in
`src/Model` references another layer, and no unit outside `src/UI` uses `Vcl.*` or shows a dialog —
errors travel out as results or exceptions and the form is what turns them into a message.

Three rules shape the code more than anything else:

- **No `TDataSet` leaves `src/Repository`.** A query turns rows into `TLogEvent` values before
  returning them, so no dataset reaches the model or the form.
- **The filter predicate exists once**, as a SQL `where` clause built by the repository. The form
  collects criteria into a `TEventFilter` and knows nothing about how they are applied, so search,
  the severity filter and the count under the table cannot disagree
  ([ADR 0007](docs/adr/0007-event-repository.md)).
- **One thread touches the database**, the main one. The generator builds an event on its own thread
  and hands it over with `TThread.Queue`, which it has to do anyway to trigger a repaint, so there is
  no shared event list and nothing to lock ([ADR 0011](docs/adr/0011-event-generator-thread.md)).

## What the window does

- **Import JSON...** appends the events in a file to the stored history. A file that is not JSON, or
  whose root is not an array, is reported and changes nothing; individual records that cannot be read
  are skipped, counted, and the first problem is named
  ([ADR 0009](docs/adr/0009-json-import-semantics.md)).
- **Clear all events** deletes the whole history, behind a confirmation whose default answer is No.
- **Search** narrows the table to events whose text contains what is typed, on every keystroke.
- **Severity** narrows it to one level, or to all of them.
- **Start generating** appends one random event a second until it is stopped. Stopping and closing the
  window both take effect immediately, because the thread waits on an event object rather than
  sleeping.
- The status bar states how many events are shown against how many are stored, so an empty table under
  a filter cannot be read as an empty database.

The table is a virtual `TListView` over the result of the current query, capped at 1000 rows
([ADR 0008](docs/adr/0008-listview-for-the-events-table.md)); the status bar says when that cap is in
effect.

## Sample data

- `tests/sample-events.json` — the good file: twelve events across all three severities, with
  the levels written in mixed case on purpose, since the match is case-insensitive.
- `tests/sample-events-invalid.json` — valid JSON whose records are broken in seven different ways,
  next to two good ones, so what a partial import does is something to look at.
- `tests/sample-events-malformed.json` — not valid JSON at all.

The last two exist because "malformed files never crash the application" is worth being able to
demonstrate rather than claim. They are also the fixtures of the DUnitX tests in
`tests/EventsLog.Json.Tests.pas`.

## Decisions

Every key technical decision is recorded in [docs/adr](docs/adr) — the grid control, the JSON parsing
strategy, the threading model, the storage choice, and what each alternative would have cost.
[docs/plan.md](docs/plan.md) tracks the requirements from the statement against what is built.

## What could be improved with more time

**Correctness and coverage**

- **Tests stop at the JSON validation.** The repository and the form have none. The repository is the
  natural next target — its `where` clause and the row-to-event conversion are pure enough to test
  against a temporary database file. There is no CI, and cannot be one, while the compiler refuses to
  run from a console.
- **Search folds case for ASCII only.** `error` finds `Error`, but `помилка` will not find `Помилка`,
  because that is as far as SQLite's `LIKE` goes without ICU. The fix is a lowercased shadow column
  filled by Delphi's Unicode-aware `ToLower`, which means a schema change and a migration
  ([ADR 0010](docs/adr/0010-search-and-severity-filter.md)).
- **Re-importing the same file stores its events twice.** Identifiers are minted on import rather than
  read from the file, so nothing distinguishes a second import from new data. De-duplication needs a
  definition of what makes two events the same.

**The table**

- **No sorting by column.** The order is always newest first.
- **The 1000-row cap is a cap, not paging.** A window of rows fetched on scroll would show a log of any
  size; the cap was chosen over it deliberately, and the status bar admits when it is reached.
- **A selected row does not follow its event.** While generating, rows shift down as new events arrive
  above them, and the selection stays at its index rather than on its event.

**The generator and the database**

- **Inserts happen on the main thread.** At one event a second this is invisible; a shorter interval or
  a slow disk would be felt in the window, and the answer would be a writer thread with its own
  connection.
- **The interval and the severity mix are fixed** — one second, and whatever the template table holds.
  Both are reasonable things for a user to set.

**Editing and state**

- **Events cannot be edited, and cannot be deleted one at a time** — *Clear all events* is
  all-or-nothing.
- **Nothing is saved back to JSON.** Import is one-way.
- **Window size, position, the active filter and the last opened file are not remembered** between
  runs.
- **The interface is English only.** UI strings go through `resourcestring`, so translating is
  mechanical, but nothing is translated.
