# 0003. UUID event identifiers

- **Status:** accepted
- **Date:** 2026-08-21

## Context

Every event carries an ID — the statement requires it and the table has to display it. The type has
to be settled now, because it appears in the record, in the JSON format, in the sample data and in a
grid column.

Capacity is not the question: at one event per second a 32-bit counter lasts 68 years, and what caps
this application is that every event lives in RAM. Coordination is the question. The application is
meant to take events from more than one source — today a JSON file plus a generator, tomorrow a
second file merged rather than replacing, or a feed from another process — and a shared counter is
the thing each new source has to reach.

## Options

### Option 1 — `Integer` or `Int64` issued by a counter in the store

- Pro: short enough to read in a grid column and in the sample JSON, and it carries order.
- Con: every producer must go through the store, which becomes a coordination point.
- Con: importing needs an explicit collision rule — easy to state, easy to forget when a second
  source appears.
- Con: unique within one run of one process only. Two files from different machines both start at 1.

### Option 2 — `TGUID`, minted by whoever creates the event

- Pro: no coordination at all; sources cannot collide, and duplicate identifiers inside a file stop
  being the store's problem.
- Pro: removes mutable state — there is no counter to keep, lock or reset.
- Con: 16 bytes instead of 8, growing every snapshot copy that ADR 0002 accepted.
- Con: `TGUID.NewGuid` is v4 and carries no order.
- Con: 36 characters in a grid column, and a noticeably less readable `sample-events.json` — itself a
  deliverable a reviewer reads.

A hand-rolled UUID v7 would restore the ordering, but writing a generator by hand in a project with
no tests, to produce a property the timestamp field already gives, was not worth it.

## Decision

Option 2 — `TGUID`, minted by the producer of the event.

The application is meant to take events from more than one source, and that is exactly the case
identifiers-without-coordination exist for. Under Option 1 every new source is routed through the
store's counter and every merge needs a renumbering rule; under Option 2 neither problem exists.

The costs are accepted with eyes open. Eight extra bytes is small against a design that already
copies snapshots. The lost ordering costs little, because a log is read in time order and the
timestamp carries that — the identifier was never what ordered events. The display cost is the one
that does not disappear, and how the identifier is rendered is left to the table's own decision.

`TLogEvent` exposes two ways in: `Create`, which takes an identifier that already exists, and `New`,
which mints one. Nothing else in the application issues identifiers.

## Consequences

A default-initialised `TLogEvent` has an all-zero identifier, which is a valid `TGUID` and not a
marker the compiler will reject. An all-zero identifier reaching the table means something built an
event by filling in fields instead of going through `New` or `Create`.
