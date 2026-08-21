# 0004. SQLite for local persistence

- **Status:** accepted
- **Date:** 2026-08-21

## Context

This decision extends the assignment rather than implementing it. The statement asks for event
history to be *imported* from a JSON file into memory; it says nothing about events surviving a
restart. Persistence is wanted for this project for two stated reasons: events should still be there
the next time the application opens, and filtering and search should be expressible as SQL rather
than as a scan over an array. That is a deliberate choice by the project owner, recorded here so that
a reviewer reads it as a decision and not as a misunderstanding of scope.

Constraints that shape it:

- Users receive a single `.exe`. Anything that needs an installer, a service or a DLL placed beside
  the executable is excluded.
- The installed RAD Studio 37.0 Personal edition includes FireDAC with the SQLite driver, verified on
  disk for both Win32 and Win64, including `FireDAC.Phys.SQLiteWrapper.Stat` — the unit that links
  the SQLite engine into the executable instead of loading `sqlite3.dll`.
- Two access patterns will exist at once: a background thread appending an event every second, and
  the UI thread reading to paint the table.
- ADR 0001 keeps `src/Model` free of anything but plain types, and keeps the form as the only place
  that knows about controls. Whatever is chosen has to live in `src/Repository` without leaking a
  dataset into either.
- Delphi has no migration tooling. Whatever schema exists is created and evolved by hand-written SQL.

## Options

### Option 1 — a JSON file rewritten when the list changes

Reuse `System.JSON`, which the import path needs anyway, and write the whole list back out.

- Pro: no new dependency whatsoever; the format stays human-readable and hand-editable.
- Pro: the same code serves import and persistence.
- Con: appending one event rewrites the entire file. At one event per second that is a full rewrite
  every second, growing linearly with the log.
- Con: a crash or a power loss during the rewrite truncates the file and loses everything, unless
  write-to-temp-and-rename is implemented by hand.
- Con: no queries. Filtering and search stay array scans, so the second reason for wanting
  persistence is not served at all.

### Option 2 — `TFDMemTable` saved to a file

FireDAC's in-memory dataset, persisted with `SaveToFile` / `LoadFromFile`.

- Pro: dataset semantics — `Filter`, `Locate`, sorting — without a database engine.
- Pro: one file, no external dependency.
- Con: still a whole-file save on every change, with the same durability problem as Option 1.
- Con: not SQL. `Filter` expressions are not queries, there are no indexes, and nothing composes.
- Con: pulls a `TDataSet` into the middle of the application, which is the shape ADR 0001 rejected:
  the natural next step is binding it straight to a grid, and the layering stops meaning anything.

### Option 3 — SQLite through FireDAC, statically linked

- Pro: real SQL — `WHERE`, `ORDER BY`, indexes, aggregate queries — which is the capability asked for.
- Pro: appending is one `INSERT`, not a rewrite. Cost does not grow with the size of the log.
- Pro: transactions and a journal, so a crash mid-write leaves a consistent database rather than a
  truncated file.
- Pro: a single file and, with the static wrapper, nothing beside the executable.
- Pro: first-party. No third-party package enters the project.
- Con: FireDAC is beyond "standard RTL and VCL", so the working rules of this repository have to be
  amended rather than quietly bent.
- Con: introduces a real write path, and with it questions the application did not have before —
  when to write, in what transaction, and from which thread.
- Con: SQLite permits one writer at a time, and a `TFDConnection` is not safe to use from two threads
  at once. Access has to be deliberately arranged, not assumed.
- Con: the schema is created and migrated by hand.

### Option 4 — a client/server database

PostgreSQL, MySQL or InterBase ToGo.

- Pro: nothing this application needs that SQLite does not already provide.
- Con: requires a server, or DLLs deployed next to the executable. Either breaks the single-`.exe`
  delivery outright.

## Decision

Option 3 — SQLite through FireDAC, with `FireDAC.Phys.SQLiteWrapper.Stat` so the engine ships inside
the executable.

Why it won: it is the only option that serves both stated reasons. Options 1 and 2 can persist, but
neither gives SQL, and both pay a whole-file rewrite for every appended event — which at one event
per second is the application's steady state, not an edge case. Option 4 gives nothing extra and
costs the delivery format.

The cost that is accepted knowingly is the dependency. FireDAC is not part of the RTL, and the rule
in `CLAUDE.md` is amended in the same change rather than reinterpreted: first-party data access is
allowed, third-party packages remain excluded.

What this does not change: `src/Model` keeps plain types. `TLogEvent` stays a record (ADR 0002) and
the repository converts rows into records, so no `TDataSet` crosses out of `src/Repository`. The UUID
identifier from ADR 0003 becomes the primary key, which is where it starts paying for itself —
imported events and generated events land in the same table with no renumbering and no counter to
coordinate.

What this decision explicitly leaves open, because each needs its own reasoning:

- Whether the UI reads a snapshot held in memory or queries the database on every filter change.
- Whether a generated event is one `INSERT` or part of a batched transaction.
- Which thread owns the connection, and whether the journal runs in WAL mode.

## Consequences

Easier: filtering and searching, which become SQL instead of array traversal; keeping a log larger
than comfortable in memory, since rows no longer all have to be resident.

Harder: the application now creates a file on the user's machine, so where that file lives is a
decision of its own (ADR 0005) and the README has to say where it is and how to reset it. Schema
changes are hand-written SQL guarded by `create table if not exists`, because there is no migration
tool. And the write path introduces concurrency the application did not have.

The scale statement in ADR 0003 changes character rather than being wrong. Identifier width was never
the limit; keeping every event in RAM was. With a database that ceiling is liftable, but only if the
UI stops holding the entire list — which is exactly the open question above.

To revisit if the assumptions change: if persistence were dropped again, or if the data outgrew a
single-file database and needed a server. Either would be a new ADR superseding this one.
