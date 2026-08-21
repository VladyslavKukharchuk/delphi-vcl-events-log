# Implementation plan

Working tracker for the "Events Log" assignment. Source of truth for scope is
[Test task Delphi Developer.docx](Test%20task%20Delphi%20Developer.docx) — this file only
restates it as a checklist.

Tick a box when the corresponding pull request is merged, not when the code is written.

## Requirements

Every requirement below comes straight from the statement.

- [ ] **R1** — An event carries an ID, a timestamp, text and a severity level (Info / Warning / Error) · *model*
- [ ] **R2** — Main window shows the events in a table, with every attribute visible · *UI*
- [ ] **R3** — Event history loads from a JSON file · *feature*
- [ ] **R4** — Malformed files and invalid data never crash the application · *quality*
- [ ] **R5** — Search events by their text · *feature*
- [ ] **R6** — Filter events by severity level · *feature*
- [ ] **R7** — The generator can be switched on and off · *UI*
- [ ] **R8** — While on, one random event is appended to the shared list every second · *feature*
- [ ] **R9** — Generation runs on a background thread and never blocks the UI · *quality*
- [ ] **R10** — Deliverable: project sources plus the built executable · *deliverable*
- [ ] **R11** — Deliverable: a JSON file with test data · *deliverable*
- [ ] **R12** — Deliverable: README stating the Delphi version, the program structure and what could be improved with more time · *deliverable*

## Beyond the statement

Wanted for this project rather than required by the statement, and recorded as deliberate extensions
in the ADRs rather than smuggled in:

- [ ] **P1** — events survive a restart: the list is loaded from and written to a local SQLite
      database ([ADR 0004](adr/0004-sqlite-for-local-persistence.md), [ADR 0005](adr/0005-database-file-location.md)) · *feature*
- [ ] **P2** — filtering and search are expressed as SQL against that database rather than as a scan
      over an array · *feature*
- [ ] **P3** — the README states where the database file lives and that deleting that folder resets
      the application to empty · *deliverable*

## Open decisions

The statement leaves these unspecified, and each one changes the code. The proposal after the
dash is what we go with unless decided otherwise; tick the box once the decision is settled and
recorded in an ADR.

- [x] **D1 — who issues IDs** — identifiers are UUIDs minted by whoever creates the event, so
      there is no counter and no coordination between imported and generated events. Recorded in
      [ADR 0003](adr/0003-uuid-event-identifiers.md).
- [ ] **D2 — import replaces or appends** — replaces, asking for confirmation when the list is
      not empty. "Event history" reads as loading a state rather than adding to one. With
      persistence, "replaces" also means deleting the stored rows, not only the in-memory list.
- [ ] **D3 — timestamp format in JSON** — ISO 8601 (`2026-08-21T07:43:12`) via
      `System.DateUtils`, local time.
- [ ] **D4 — severity in JSON** — a case-insensitive string; an unknown value makes the record
      invalid (skipped and reported) instead of silently becoming Info.
- [ ] **D5 — auto-scroll while generating** — no forced scrolling, otherwise the list cannot be
      read while events keep arriving.
- [ ] **D6 — executable bitness for delivery** — ship both Win32 and Win64 in the release.
- [ ] **D7 — how the identifier is displayed** — a 36-character UUID does not belong in a grid
      column next to a message; most likely a shortened form with the full value available on demand.
      Decided together with the table.
- [x] **D8 — what the UI reads** — SQL does the filtering and the result is materialised into an
      array that the virtual list reads by index; the unfiltered view is the most recent rows by
      time, bounded by a limit. Memory holds the result, not the whole log. True paging with windows
      fetched on scroll was rejected as over-engineering here.
- [ ] **D9 — when a generated event is written** — one INSERT per event, or a batched transaction.
      One row per second is modest, but in SQLite it is the transaction, not the row, that costs.
- [ ] **D10 — which thread owns the connection** — a `TFDConnection` is not safe to share between
      threads and SQLite allows one writer. Either the generator posts to the UI thread and a single
      connection serves everything, or it gets its own connection and the journal runs in WAL mode.

## Out of scope

Not asked for by the statement and not wanted for this project either, so deliberately not built. These belong in the README section
about what could be improved with more time:

- Unit tests.
- Saving the list back to JSON.
- Editing or deleting events.
- Sorting by column.
- Persisting window state, filters or the last opened file.
