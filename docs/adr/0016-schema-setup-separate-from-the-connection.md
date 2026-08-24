# 0016. Schema setup separate from the connection object

- **Status:** accepted
- **Date:** 2026-08-24

## Context

ADR 0004 chose SQLite, ADR 0005 chose the file location, ADR 0006 fixed the schema — one `events`
table plus two indexes, created by hand-written `create ... if not exists` statements because Delphi
has no migration tooling. ADR 0007 introduced `TEventRepository` and ADR 0013 made it an interface
resolved in the composition root.

Those statements ended up in `EventsLog.Database`, beside the code that resolves the file path, opens
the `TFDConnection` and sets the SQLite pragmas. The class was called `TEventsDatabase`, and the name
was accurate: it really was *the events database*, connection and schema in one object.

Two things about that arrangement are worth deciding rather than leaving to drift, and they are
coupled — which is why one record covers both.

**The unit mixes two levels.** Where the file lives and how the connection is configured is true of
any table this application might store. Which columns `events` has is true of exactly one caller, the
repository, and ADR 0006 already established that only `src/Repository` converts values for that
table. Adding a second table would force the question anyway: its DDL either joins `EnsureSchema` and
the "database" grows a list of every table in the application, or it lands somewhere else and the
schema lives in two places.

**The type name repeats itself.** Fully qualified it reads `EventsLog.Database.TEventsDatabase`. The
convention in CLAUDE.md is that the unit name carries the context and the type name carries the role,
which the duplicated `Events` works against. But the name cannot be shortened on its own: a
`TDatabase` that still creates the `events` table would claim to be table-agnostic while naming
`events` three times, and a reader trusts a short name more than a long one. The rename is only
available if the schema moves.

One clarification about scope, because the vocabulary invites more than is being built. What these
statements do is *bootstrap*: `create ... if not exists` handles "the file is new" and nothing else.
It does not handle "the file exists in an older shape", which is what a migration is for. A future
column would need an `alter table` and a decision about existing files, exactly as ADR 0006 already
stated. Whatever is decided here should be named for what it does, not for what it resembles.

## Options

Two questions, each with its own alternatives.

### Where the schema statements live

- **In the connection object, as they are.** Pro: no change, and the name `TEventsDatabase` stays
  honest. Pro: the DDL runs once per connection, structurally guaranteed. Con: `src/Repository` has
  its table described in two units — columns in `EventsLog.Database`, every statement against those
  columns in `EventsLog.EventRepository`. Con: a second table has nowhere obvious to go.

- **In `TEventRepository`, run from its constructor.** The DDL moves next to the `insert` and
  `select` statements that use those columns, and `Create` calls a private `EnsureSchema` before
  returning. Pro: one unit then describes the `events` table completely — its columns and every
  statement against them. Pro: a second table brings its own DDL in its own repository, with no
  shared list to edit. Con: constructing a data-access object mutates the database structure, and
  that is invisible at the call site — `Create(ADatabase)` reads as "give me something that can query
  events". Con: nothing then decides the order between two repositories' DDL, and an index spanning
  two tables has no home. Con: schema creation runs on every construction rather than once.

- **In their own unit, run once by the composition root.** A `EventsLog.Schema` unit in
  `src/Repository` holds the statements and a single `EnsureSchema(ADatabase: TDatabase)`, called
  from `EventsLog.dpr` between opening the connection and building the repository. Pro: the startup
  sequence reads in order — open the file, prepare the schema, build the repository — with no hidden
  work. Pro: the repository's constructor does nothing but store a reference. Pro: a second table
  adds statements to one place, in a defined order. Con: the table's columns are described in a
  different unit from the statements that read them. Con: one more unit and one more line in the
  composition root.

- **In a versioned migration runner.** `EventsLog.Migrations` holding an array of steps, using
  `PRAGMA user_version` as the counter, applying only steps above the stored version, each in a
  transaction. Pro: a real upgrade path — existing database files can gain columns without being
  deleted. Pro: `user_version` is built into SQLite, so no journal table is needed. Con: roughly
  sixty lines of machinery for a schema with one version, in an application whose statement does not
  ask for schema evolution; CLAUDE.md's rule against adding features "just in case" points directly
  at this. Con: the second migration is the one that proves a runner works, and a runner with a
  single step is untested by use.

### What the connection class is called

- **`TEventsDatabase`.** Pro: accurate while the class owns the schema, and no change to make. Con:
  the duplicated `Events` in the qualified name, against the convention in CLAUDE.md.

- **`TDatabase`.** Pro: the unit name already says `EventsLog`, so the type is free to carry only the
  role. Pro: no clash — the legacy `TDatabase` belongs to the BDE units, which this project neither
  uses nor has installed. Con: only defensible if the schema moves out; otherwise the short name
  misleads.

The exception class has no such freedom. `EDatabaseError`, the obvious counterpart to `TDatabase`, is
already declared in `Data.DB`, which arrives transitively through `FireDAC.Comp.Client`.

## Decision

The schema statements move to their own unit, and the class is renamed.

`src/Repository/EventsLog.Schema.pas` holds the three statements and a single
`EnsureSchema(ADatabase: TDatabase)`, wrapped so a failure surfaces as `ESchemaCreateError` naming the
database file. `EventsLog.Database` keeps the directory, the connection and the pragmas, and its class
becomes `TDatabase` with `EEventsDatabaseError` renamed `EDatabaseOpenError`. The composition root
calls the schema step once:

```pascal
Database := TDatabase.Create;
EnsureSchema(Database);
Repository := TEventRepository.Create(Database);
```

Why a separate unit won over leaving the DDL in the connection object: the two levels in that unit
have different lifetimes and different audiences, and keeping them together is what blocks the rename.
Separating them costs one file and buys a startup sequence that states its own order.

Why it won over putting the DDL in the repository — the closest alternative, and the one with the
better-sounding argument. Cohesion of *statements about a table* is real but weak: the columns already
appear in `SqlInsert` and `RowToEvent`, so a change to the table touches the repository wherever the
DDL lives. What that option costs is a constructor whose contract is wider than its name, and a
startup order that exists only implicitly. Preparing a schema and reading rows are different concerns
at different times; coupling "I want to read events" to "I mutate the database structure" is the
problem, independent of how many times it happens. This is the same separation every ecosystem with
migration tooling arrives at — the schema step runs in `main`, before the data-access objects are
built. Delphi has no such tooling, so the step is written by hand, but where it runs is still a
choice and it is the same choice.

Why it won over a versioned runner: the assignment does not ask for schema evolution, and this
application ships one version of one table. A runner would be machinery built for a case that will
not arrive during the life of this codebase. `EnsureSchema` is also the natural seam if that ever
changes — a runner replaces the body of one procedure and one call site.

The con accepted is that the columns are now defined one unit away from the code that reads them.
Both units are in `src/Repository`, ADR 0006 remains the written description of the schema, and the
compiler catches the mismatch that matters: a column the repository selects and the schema does not
create fails on the first query.

## Consequences

Easier: reading the startup sequence, which is three lines in one place with no hidden work. Adding a
second table — its statements join `EnsureSchema` in a defined order rather than appearing in
whichever constructor happens to run first. Replacing bootstrap with real migrations later — one
procedure body and one call site.

Harder: a change to the `events` table now touches two units in `src/Repository` rather than one, and
reading `EventsLog.Database` alone no longer tells you what the file contains. That answer moved to
`EventsLog.Schema` and to ADR 0006.

`EventsLog.Database` keeps `FireDAC.DatS`, `FireDAC.DApt.Intf` and `FireDAC.DApt` in its `uses` clause
even though it now issues no query of its own. FireDAC links dataset support only when a DApt unit is
used somewhere in the project, and dropping them would leave every `TFDQuery` failing at run time. The
clause carries a comment saying so, because it otherwise reads as a leftover.

Earlier ADRs are append-only and still refer to `TEventsDatabase`; that name is historical from this
record onwards.

To revisit if the assumptions change: a second table, or the first change to an existing column.
Either turns `create ... if not exists` from sufficient into wrong, and the answer then is the
versioned runner.
