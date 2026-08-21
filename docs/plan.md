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

## Open decisions

The statement leaves these unspecified, and each one changes the code. The proposal after the
dash is what we go with unless decided otherwise; tick the box once the decision is settled and
recorded in an ADR.

- [ ] **D1 — who issues IDs** — the store issues sequential IDs; on import the counter moves
      past the highest ID in the file, so the generator cannot produce duplicates.
- [ ] **D2 — import replaces or appends** — replaces, asking for confirmation when the list is
      not empty. "Event history" reads as loading a state rather than adding to one.
- [ ] **D3 — timestamp format in JSON** — ISO 8601 (`2026-08-21T07:43:12`) via
      `System.DateUtils`, local time.
- [ ] **D4 — severity in JSON** — a case-insensitive string; an unknown value makes the record
      invalid (skipped and reported) instead of silently becoming Info.
- [ ] **D5 — auto-scroll while generating** — no forced scrolling, otherwise the list cannot be
      read while events keep arriving.
- [ ] **D6 — executable bitness for delivery** — ship both Win32 and Win64 in the release.

## Out of scope

Not asked for by the statement, so deliberately not built. These belong in the README section
about what could be improved with more time:

- Unit tests.
- Saving the list back to JSON.
- Editing or deleting events.
- Sorting by column.
- Persisting window state, filters or the last opened file.
