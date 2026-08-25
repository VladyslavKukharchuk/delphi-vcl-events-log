# 0004. SQLite for local persistence

- **Status:** accepted
- **Date:** 2026-08-21

## Context

This decision extends the assignment rather than implementing it. The statement asks for history to
be *imported* from JSON into memory; it says nothing about surviving a restart. Persistence is wanted
here for two stated reasons — events should still be there next time the application opens, and
filtering and search should be expressible as SQL rather than as a scan over an array. Recorded so
that a reviewer reads it as a decision and not as a misunderstanding of scope.

- Users receive a single `.exe`. Anything needing an installer, a service or a DLL beside the
  executable is excluded — which rules out a client/server database outright.
- RAD Studio 37.0 Personal includes FireDAC with the SQLite driver, verified on disk for Win32 and
  Win64, including `FireDAC.Phys.SQLiteWrapper.Stat` — the unit that links SQLite into the executable
  instead of loading `sqlite3.dll`.
- A background thread will append while the UI thread reads.
- ADR 0001 keeps `src/Model` free of anything but plain types, so nothing chosen here may leak a
  dataset out of `src/Repository`.

## Options

### Option 1 — a JSON file rewritten when the list changes

- Pro: no new dependency; the same code serves import and persistence, and the format stays readable.
- Con: appending one event rewrites the entire file — every second, growing linearly.
- Con: a crash mid-rewrite truncates the file unless write-to-temp-and-rename is hand-written.
- Con: no queries, so the second reason for wanting persistence is not served at all.

### Option 2 — `TFDMemTable` saved to a file

- Pro: dataset semantics — `Filter`, `Locate`, sorting — without a database engine.
- Con: still a whole-file save on every change.
- Con: not SQL. No indexes, and nothing composes.
- Con: pulls a `TDataSet` into the middle of the application, which is the shape ADR 0001 rejected.

### Option 3 — SQLite through FireDAC, statically linked

- Pro: real SQL — `where`, `order by`, indexes — which is the capability asked for.
- Pro: appending is one `insert`, not a rewrite, and transactions survive a crash mid-write.
- Pro: a single file, nothing beside the executable, and first-party.
- Con: FireDAC is beyond "standard RTL and VCL", so the repository rules have to be amended rather
  than quietly bent.
- Con: SQLite permits one writer, and a `TFDConnection` is not thread-safe. Access has to be
  deliberately arranged.
- Con: the schema is created and migrated by hand — Delphi has no migration tooling.

## Decision

Option 3 — SQLite through FireDAC, with `FireDAC.Phys.SQLiteWrapper.Stat`.

It is the only option serving both stated reasons. Options 1 and 2 can persist but give no SQL, and
both pay a whole-file rewrite for every appended event — which at one event per second is the
steady state, not an edge case.

The cost accepted knowingly is the dependency: the rule in `CLAUDE.md` is amended in the same change,
allowing first-party data access and still excluding third-party packages. `src/Model` keeps plain
types, and the repository converts rows into records so no `TDataSet` crosses out of
`src/Repository`. The UUID from ADR 0003 becomes the primary key, which is where it starts paying for
itself — imported and generated events land in one table with no renumbering.

Left open deliberately, each needing its own reasoning: whether the UI queries on every filter change
or holds a snapshot; whether a generated event is one `insert` or a batch; which thread owns the
connection.

## Consequences

The application now creates a file on the user's machine, so where it lives is a decision of its own
([ADR 0005](0005-database-file-location.md)) and the README has to say how to reset it. The scale
statement in ADR 0003 changes character rather than being wrong: identifier width was never the
limit, keeping every event in RAM was, and that ceiling is now liftable — but only if the UI stops
holding the entire list.
