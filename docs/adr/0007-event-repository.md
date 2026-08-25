# 0007. Writes, connection ownership and how the view refreshes

- **Status:** accepted; the import half is revised by [ADR 0009](0009-json-import-semantics.md)
- **Date:** 2026-08-21

## Context

ADR 0004 put the events in SQLite and ADR 0006 fixed the schema. What is left is how the application
writes and reads: the generator produces an event every second, the user changes a filter, and an
import replaces the whole history. Three questions have to be answered together, because each
constrains the others — when a generated event is written, which thread owns the connection, and how
the table learns about a write.

- One event per second is the load. Not a thousand; one.
- The UI has to be told about a new event regardless of where it was written, so that notification
  already crosses from the generator thread to the UI thread.
- A `TFDConnection` is not safe to use from two threads at once, and SQLite permits a single writer.

## Options

### When to write

1. **One `insert` per event.** Pro: an event is durable the moment it exists; no state to flush or
   lose. Con: one transaction per second — in SQLite the transaction, not the row, is the cost.
2. **Buffer and flush on a timer.** Pro: amortises the transaction cost. Con: a buffer, a timer and a
   shutdown flush, plus a window where events exist on screen but not on disk — throughput this
   application does not need.

### Who owns the connection

1. **One connection, owned by the UI thread.** The generator hands the event over with
   `TThread.Queue`; the UI thread inserts it. Pro: the database is never touched by two threads, and
   no shared mutable state exists at all. Con: the insert happens on the UI thread.
2. **A connection per thread**, WAL keeping reader and writer apart. Pro: writes never touch the UI
   thread. Con: two connections, a second schema check, and the single-writer rule becomes something
   the code must respect rather than something it cannot violate.
3. **One connection guarded by a lock.** Con: every caller has to remember the lock, and a held lock
   on the UI thread is a frozen window anyway.

### How the view refreshes

1. **Re-run the current query.** Pro: the predicate exists once, in SQL. Con: a query per insert.
2. **Append to the array if the event matches the current filter.** Pro: no query. Con: the predicate
   then exists twice — SQL in the repository, Pascal in the filter — and two implementations of one
   rule drift.

## Decision

**One `insert` per event; import in one transaction. One connection, owned by the UI thread. Re-run
the query after a write.**

The generator's writes go in as they arrive; `ReplaceAll` gets the opposite treatment, a delete plus
every insert in one explicit transaction, because an imported file may hold thousands of rows. The
rule is not "always batch" or "never batch" but "batch what arrives in bulk".

The connection sits on the UI thread because the crossing already exists: the event travels there to
repaint the table whether or not the write does, so sending the write along the same path costs
nothing and buys an application where only one thread touches the database. If a single-row insert
into a local file ever became visible, option 2 is the escape hatch and it is a local change.

Re-running the query won because duplicating the predicate is the cheaper option that eventually
shows the wrong rows. So `TEventFilter` carries criteria and no `Matches` method: exactly one place
decides what matches, and it is the `where` clause. Refreshes are coalesced so a burst cannot queue a
query per event.

A consequence worth stating plainly: **there is no shared event list.** The generator holds nothing
the UI reads, and the array behind the table is created and read on the UI thread only. The rule in
`CLAUDE.md` about guarding a shared list has nothing left to guard, so it is amended in the same
change rather than left standing as advice about code that does not exist.

## Consequences

`Insert` outside a transaction means a failed write fails alone, which is correct for a generated
event and wrong for an import — hence the two methods. Nothing in the type system distinguishes them,
so the naming has to: `Insert` for one, `ReplaceAll` for the bulk case.
