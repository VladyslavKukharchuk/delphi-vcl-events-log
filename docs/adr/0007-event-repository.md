# 0007. Writes, connection ownership and how the view refreshes

- **Status:** accepted; the import half of D9 is revised by [ADR 0009](0009-json-import-semantics.md)
- **Date:** 2026-08-21

## Context

ADR 0004 put the events in SQLite, ADR 0006 fixed the schema, and decision D8 settled that SQL does
the filtering and the result is materialised into an array the table reads. What is left is how the
application actually writes and reads: the generator produces an event every second, the user changes
a filter, and an import replaces the whole history.

Three questions have to be answered together, because each constrains the others:

- **When is a generated event written** — immediately, or buffered and flushed?
- **Which thread owns the connection** — a `TFDConnection` is not safe to use from two threads at
  once, and SQLite permits a single writer.
- **After a write, how does the table learn about it** — by re-running the query, or by adding the new
  event to the array the table is already showing?

Constraints:

- One event per second is the load. Not a thousand; one.
- The UI has to be told about a new event regardless of where it was written, because the table has to
  repaint. That notification already crosses from the generator thread to the UI thread.
- `src/UI` is the only place allowed to touch controls, and `src/Repository` the only place allowed to
  speak SQL (ADR 0001, ADR 0004).

## Options

### When to write

1. **One `INSERT` per event.** Pro: an event is durable the moment it exists, and there is no state to
   flush or lose. Con: one transaction per second — in SQLite the transaction, not the row, is the
   expensive part.
2. **Buffer and flush on a timer.** Pro: amortises the transaction cost over many rows. Con: adds a
   buffer, a timer and a shutdown flush, and creates a window in which events exist on screen but not
   on disk. Con: buys throughput this application does not need.

### Who owns the connection

1. **One connection, owned by the UI thread.** The generator builds an event and hands it over with
   `TThread.Queue`; the UI thread inserts it. Pro: the database is never touched by two threads, so
   there is nothing to synchronise and nothing to get wrong. Pro: no shared mutable state exists at
   all — the generator owns nothing the UI reads. Con: the `INSERT` happens on the UI thread, so a
   slow write would be a frozen window.
2. **A connection per thread.** The generator writes on its own connection; WAL keeps the reader and
   the writer apart. Pro: writes never touch the UI thread. Con: two connections, a second schema
   check, and SQLite's single-writer rule becomes something the code has to respect rather than
   something it cannot violate.
3. **One connection guarded by a lock.** Pro: one connection, writes off the UI thread. Con: every
   caller has to remember the lock, and a held lock on the UI thread is a frozen window anyway.

### How the view refreshes

1. **Re-run the current query.** Pro: the predicate exists once, in SQL. Whatever the table shows is
   what the database would return. Con: a query per insert.
2. **Append to the array if the event matches the current filter.** Pro: no query. Con: the predicate
   now exists twice — once as SQL in the repository, once as Pascal in the filter — and two
   implementations of one rule drift. Con: correctness also depends on the row limit and the sort
   order being reproduced by hand.

## Decision

**One `INSERT` per event; import in one transaction.** The generator's writes go in as they arrive.
`ReplaceAll` is the opposite case and gets the opposite treatment: a delete plus every insert inside
one explicit transaction, because an imported file may hold thousands of rows and a transaction per
row there is the difference between instant and visibly slow. The rule is not "always batch" or "never
batch" but "batch what arrives in bulk".

**One connection, owned by the UI thread.** The reason is not simplicity in the abstract, it is that
the crossing already exists: the UI has to be told about a new event in order to repaint, so the event
travels to the UI thread whether or not the write does. Sending the write along the same path costs
nothing and buys an application in which the database is only ever touched by one thread. A single-row
insert into a local SQLite file with WAL is measured in microseconds; if that ever became visible,
option 2 is the escape hatch and it is a local change.

**Re-run the query after a write.** Duplicating the predicate — SQL in the repository, Pascal in the
filter — would be the cheaper option and the one that eventually shows the wrong rows, because the two
copies have no way to stay in step. So `TEventFilter` carries criteria and no `Matches` method: there
is exactly one place that decides what matches, and it is the `where` clause. Refreshes are coalesced
so a burst cannot queue a query per event.

A consequence worth stating plainly: **there is no shared event list.** The generator holds nothing the
UI reads, and the array behind the table is created and read on the UI thread only. The rule in
`CLAUDE.md` about guarding a shared list with a lock has nothing left to guard, so it is amended in the
same change rather than left standing as advice about code that does not exist.

## Consequences

Easier: reasoning about threads, because only one touches the database and only one touches the array.
Reviewing the filter, because there is one predicate. Trusting the table, because it shows the result
of a query rather than a hand-maintained approximation of one.

Harder: the UI thread now does I/O, which is a thing to watch rather than a thing to fear at this size.
And every insert costs a query, so refresh coalescing is not an optimisation but part of the design.

To revisit if the assumptions change: an event rate high enough for per-event transactions or
per-insert queries to show up, or a second writer such as a network feed. The first would move writes
off the UI thread; the second would make a connection per producer unavoidable. Either is a new ADR.

The consequence to watch: `Insert` outside a transaction means a failed write fails alone, which is
correct for a generated event and wrong for an import — hence the two different methods. Nothing in the
type system distinguishes them, so the naming has to: `Insert` for one, `ReplaceAll` for the bulk case.
