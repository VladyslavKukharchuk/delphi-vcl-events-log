# 0016. Schema setup separate from the connection object

- **Status:** accepted
- **Date:** 2026-08-24

## Context

ADR 0006 fixed the schema — one `events` table plus two indexes, created by hand-written
`create ... if not exists` statements because Delphi has no migration tooling. Those statements ended
up in `EventsLog.Database`, beside the code that resolves the file path, opens the `TFDConnection`
and sets the SQLite pragmas. The class was called `TEventsDatabase`, and the name was accurate: it
really was *the events database*, connection and schema in one object.

Two things about that are worth deciding rather than leaving to drift, and they are coupled.

**The unit mixes two levels.** Where the file lives and how the connection is configured is true of
any table this application might store. Which columns `events` has is true of exactly one caller. A
second table would force the question anyway: its DDL either joins `EnsureSchema` and the "database"
grows a list of every table, or it lands elsewhere and the schema lives in two places.

**The type name repeats itself.** Fully qualified it reads `EventsLog.Database.TEventsDatabase`,
against the convention that the unit name carries the context and the type name the role. But the
name cannot be shortened on its own: a `TDatabase` that still creates the `events` table would claim
to be table-agnostic while naming `events` three times. The rename is only available if the schema
moves.

One clarification about scope. What these statements do is *bootstrap*: `create ... if not exists`
handles "the file is new" and nothing else. It does not handle "the file exists in an older shape",
which is what a migration is for. Whatever is decided here should be named for what it does.

## Options

### Where the schema statements live

- **In the connection object, as they are.** Pro: no change, and the name stays honest; the DDL runs
  once per connection, structurally guaranteed. Con: `src/Repository` has its table described in two
  units, and a second table has nowhere obvious to go.
- **In `TEventRepository`, run from its constructor.** Pro: one unit then describes the `events` table
  completely — its columns and every statement against them; a second table brings its own DDL with
  no shared list to edit. Con: constructing a data-access object mutates the database structure, and
  that is invisible at the call site. Con: nothing decides the order between two repositories' DDL,
  and an index spanning two tables has no home.
- **In their own unit, run once by the composition root.** A `EventsLog.Schema` unit in
  `src/Repository` with a single `EnsureSchema(ADatabase: TDatabase)`, called from `EventsLog.dpr`
  between opening the connection and building the repository. Pro: the startup sequence reads in
  order, with no hidden work, and the repository's constructor does nothing but store a reference.
  Con: the columns are described in a different unit from the statements that read them.
- **In a versioned migration runner**, using `PRAGMA user_version` as the counter. Pro: a real upgrade
  path — existing files can gain columns without being deleted. Con: roughly sixty lines of machinery
  for a schema with one version, in an application whose statement does not ask for schema evolution.
  Con: the second migration is the one that proves a runner works.

### What the connection class is called

`TEventsDatabase` is accurate while the class owns the schema, and duplicated in the qualified name
otherwise. `TDatabase` is free of that and does not clash — the legacy `TDatabase` belongs to the BDE
units, which this project neither uses nor has installed. The exception class has no such freedom:
`EDatabaseError` is already declared in `Data.DB`, which arrives transitively through
`FireDAC.Comp.Client`.

## Decision

The schema statements move to their own unit, and the class is renamed.
`src/Repository/EventsLog.Schema.pas` holds the three statements and a single `EnsureSchema`, wrapped
so a failure surfaces as `ESchemaCreateError` naming the database file. `EventsLog.Database` keeps
the directory, the connection and the pragmas; its class becomes `TDatabase` and
`EEventsDatabaseError` becomes `EDatabaseOpenError`. The composition root calls the schema step once:

```pascal
Database := TDatabase.Create;
EnsureSchema(Database);
Repository := TEventRepository.Create(Database);
```

Why a separate unit won over leaving the DDL in the connection object: the two levels have different
lifetimes and different audiences, and keeping them together is what blocks the rename.

Why it won over putting the DDL in the repository — the closest alternative, with the better-sounding
argument. Cohesion of *statements about a table* is real but weak: the columns already appear in
`SqlInsert` and `RowToEvent`, so a change to the table touches the repository wherever the DDL lives.
What that option costs is a constructor whose contract is wider than its name, and a startup order
that exists only implicitly. Coupling "I want to read events" to "I mutate the database structure" is
the problem, independent of how often it happens. This is the same separation every ecosystem with
migration tooling arrives at — the schema step runs in `main`, before the data-access objects are
built.

Why it won over a versioned runner: the assignment does not ask for schema evolution, and this
application ships one version of one table. `EnsureSchema` is also the natural seam if that changes —
a runner replaces the body of one procedure and one call site.

## Consequences

`EventsLog.Database` keeps `FireDAC.DatS`, `FireDAC.DApt.Intf` and `FireDAC.DApt` in its `uses`
clause even though it now issues no query of its own. FireDAC links dataset support only when a DApt
unit is used somewhere in the project, and dropping them would leave every `TFDQuery` failing at run
time. The clause carries a comment saying so, because it otherwise reads as a leftover.

Earlier ADRs are append-only and still refer to `TEventsDatabase`; that name is historical from this
record onwards.
