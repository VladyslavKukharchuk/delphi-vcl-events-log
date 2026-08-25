# Implementation plan

Working tracker for the "Events Log" assignment. Source of truth for scope is
[Test task Delphi Developer.md](Test%20task%20Delphi%20Developer.md) — this file only
restates it as a checklist.

Tick a box when the corresponding pull request is merged, not when the code is written.

## Requirements

Every requirement below comes straight from the statement.

- [x] **R1** — An event carries an ID, a timestamp, text and a severity level (Info / Warning / Error) · *model*
- [x] **R2** — Main window shows the events in a table, with every attribute visible · *UI*
- [x] **R3** — Event history loads from a JSON file · *feature*
- [x] **R4** — Malformed files and invalid data never crash the application · *quality*
- [x] **R5** — Search events by their text · *feature*
- [x] **R6** — Filter events by severity level · *feature*
- [x] **R7** — The generator can be switched on and off · *UI*
- [x] **R8** — While on, one random event is appended to the shared list every second · *feature*
- [x] **R9** — Generation runs on a background thread and never blocks the UI · *quality*
- [ ] **R10** — Deliverable: project sources plus the built executable · *deliverable*
- [x] **R11** — Deliverable: a JSON file with test data · *deliverable*
- [ ] **R12** — Deliverable: README stating the Delphi version, the program structure and what could be improved with more time · *deliverable*

## Beyond the statement

Wanted for this project rather than required by the statement, and recorded as deliberate extensions
in the ADRs rather than smuggled in:

- [x] **P1** — events survive a restart: the list is loaded from and written to a local SQLite
      database ([ADR 0004](adr/0004-sqlite-for-local-persistence.md), [ADR 0005](adr/0005-database-file-location.md)) · *feature*
- [x] **P2** — filtering and search are expressed as SQL against that database rather than as a scan
      over an array · *feature*
- [ ] **P3** — the README states where the database file lives and that deleting that folder resets
      the application to empty · *deliverable*
- [x] **P4** — the window can clear the stored history, since nothing else in the application removes
      events ([ADR 0009](adr/0009-json-import-semantics.md)) · *feature*
- [x] **P5** — the JSON validation is covered by DUnitX table tests, using the sample files as
      fixtures. Runnable from the IDE only, since Personal edition refuses command-line compiling ·
      *quality*

## Open decisions

The statement leaves these unspecified, and each one changes the code. The proposal after the
dash is what we go with unless decided otherwise; tick the box once the decision is settled and
recorded in an ADR.

- [x] **D1 — who issues IDs** — identifiers are UUIDs minted by whoever creates the event, so
      there is no counter and no coordination between imported and generated events. Recorded in
      [ADR 0003](adr/0003-uuid-event-identifiers.md).
- [x] **D2 — import replaces or appends** — appends. The store is a log that grows from two
      directions, the generator over time and each import, so replacement would discard what the
      generator recorded. Identifiers are minted on import rather than read from the file, so
      re-importing the same file stores its events twice.
      [ADR 0009](adr/0009-json-import-semantics.md).
- [x] **D3 — timestamp format in JSON** — ISO 8601 (`2026-08-21T07:43:12.160`),
      fixed width and local time, shared with the database column. Recorded in
      [ADR 0006](adr/0006-database-schema-and-encodings.md); `TimeToText` / `TryTextToTime` implement it.
- [x] **D4 — severity in JSON** — a case-insensitive string; an unknown value makes the record
      invalid (skipped and reported) instead of silently becoming Info. `TryStrToSeverity` compares
      against `SeverityNames` with `SameText`.
- [x] **D5 — auto-scroll while generating** — none, and the ordering makes it moot: the query is
      `order by time desc`, so a new event appears at the top, which is where the list already is.
      Forced scrolling would take away the position the reader chose once a second.
      [ADR 0011](adr/0011-event-generator-thread.md).
- [ ] **D6 — executable bitness for delivery** — ship both Win32 and Win64 in the release.
- [x] **D7 — how the identifier is displayed** — in full. A truncated UUID is shorter but cannot be
      copied, compared or pasted into a query, and the statement asks for the attributes to be shown
      rather than hinted at. The cost is a 250-pixel column and a 1000-pixel window.
      [ADR 0008](adr/0008-listview-for-the-events-table.md).
- [x] **D8 — what the UI reads** — SQL does the filtering and the result is materialised into an
      array that the virtual list reads by index; the unfiltered view is the most recent rows by
      time, bounded by a limit. Memory holds the result, not the whole log. True paging with windows
      fetched on scroll was rejected as over-engineering here.
- [x] **D9 — when a generated event is written** — one INSERT per event; import instead wraps the
      delete and every insert in one explicit transaction. Batch what arrives in bulk, not what
      arrives one row a second. [ADR 0007](adr/0007-event-repository.md).
- [x] **D10 — which thread owns the connection** — the UI thread, and only it. The generator hands
      the event over with `TThread.Queue`, which it must do anyway to trigger a repaint, so the
      database is never touched by two threads. [ADR 0007](adr/0007-event-repository.md).
- [x] **D11 — how the view refreshes after a write** — re-run the current query, coalesced. Appending
      to the array would duplicate the predicate as Pascal beside the SQL, and two copies of one rule
      drift. [ADR 0007](adr/0007-event-repository.md).
- [x] **D12 — case-insensitive search beyond ASCII** — accepted as a limit rather than fixed. SQLite's
      LIKE folds ASCII only, so searching "помилка" will not match "Помилка". A lowercased shadow
      column would cost a schema change, a migration and a second copy of every message on disk, for
      text this application never produces. Recorded in
      [ADR 0010](adr/0010-search-and-severity-filter.md); the README states the limit under what could
      be improved.
