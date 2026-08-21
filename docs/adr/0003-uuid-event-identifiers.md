# 0003. UUID event identifiers

- **Status:** accepted
- **Date:** 2026-08-21

## Context

Every event carries an ID — the statement requires it as an attribute and the table has to display
it. The type has to be settled now, because it appears in the record, in the JSON format, in the
sample data and in a grid column, and changing it later touches all four.

Two different concerns hide behind the question "will this scale?".

- **Capacity** is not one of them. At the one event per second the statement asks for, a 32-bit
  counter lasts 68 years. What actually caps the number of events this application can hold is that
  every event lives in a list in RAM, and a wider identifier makes that slightly worse rather than
  better.
- **Coordination** is the real question. Identifiers minted by a central counter require every
  producer to consult it. Identifiers that carry their own uniqueness do not.

The force that decides this ADR is a direction for the application rather than a line in the
statement: events are expected to arrive from more than one source. Today that is a JSON file whose
events already carry identifiers plus a generator inventing new ones; the same shape covers a second
file merged rather than replacing the list, a feed from another process, or anything remote. In every
one of those cases a shared counter is the thing that has to be coordinated, and coordination is what
goes wrong.

## Options

### Option 1 — `Integer` or `Int64` issued by a counter in the store

- Pro: four or eight bytes, and short enough to read in a grid column and in the sample JSON.
- Pro: the identifier carries order — a larger value means a later event.
- Con: every producer must go through the store to get an identifier, so the store becomes a
  coordination point that each new source has to reach.
- Con: importing a file needs an explicit collision rule — scan the imported identifiers, find the
  highest, continue past it. That rule is easy to state and easy to forget when a second source
  appears.
- Con: identifiers are only unique within one run of one process. Two files exported from different
  machines both start at 1.

### Option 2 — `TGUID`, minted by whoever creates the event

- Pro: no coordination at all. The generator, a file loader and any future source each mint their own
  identifiers, and they cannot collide. Duplicate identifiers inside a file stop being a problem the
  store has to police.
- Pro: identifiers stay unique across processes, machines and files, so events from different sources
  can be merged without renumbering anything.
- Pro: removes a piece of state from the store — there is no counter to keep, lock or reset.
- Con: 16 bytes instead of 8 grows the record from roughly 32 to roughly 40 bytes, and with it every
  snapshot copy that ADR 0002 accepted.
- Con: a v4 UUID carries no order. `TGUID.NewGuid` is v4; UUID v7, which puts a timestamp in the high
  bits, has no generator in the RTL and would have to be hand-rolled.
- Con: 36 characters plus braces in a grid column, against a handful of digits, and a noticeably less
  readable `sample-events.json` — and that file is itself a deliverable a reviewer reads.

### Option 3 — a hand-rolled UUID v7

- Pro: everything Option 2 gives, plus identifiers that sort by creation time.
- Con: writing a UUID generator by hand, with no test suite in a project that has no tests, to
  produce a property the timestamp field already provides.

## Decision

Option 2 — `TGUID`, minted by the producer of the event.

Why it won: the application is meant to take events from more than one source, and that is exactly
the case identifiers-without-coordination exist for. Under Option 1 every new source has to be routed
through the store's counter and every merge needs a renumbering rule; under Option 2 neither problem
exists, and the store loses a piece of mutable state rather than gaining one.

The costs are accepted with eyes open. Eight extra bytes per event is real but small against a design
that already copies snapshots. The loss of ordering in the identifier costs little in practice,
because a log is read in time order and the timestamp field carries that, while insertion order is
preserved by the list itself — the identifier was never the thing that ordered events. Option 3 was
rejected because hand-writing a v7 generator buys back an ordering the timestamp already gives us.

The display cost is the one that does not disappear: 36 characters do not belong in a grid column next
to a message. How the identifier is shown is left open deliberately and decided with the table, not
here — most likely a shortened form, with the full value available on demand.

Concretely, `TLogEvent` exposes two ways in: `Create`, which takes an identifier that already exists
— an event reconstructed from a file keeps the identifier the file gave it — and `New`, which mints
one. Nothing else in the application issues identifiers.

## Consequences

Easier: adding a source of events; merging two files; reasoning about uniqueness, which becomes a
property of the identifier rather than an invariant somebody maintains. The store needs no counter,
so the question of what happens to it on import disappears.

Harder: reading the sample JSON and the table. Both are deliverables, so the table needs a deliberate
answer for how it renders an identifier, and the sample file becomes something a human is less likely
to hand-edit.

To revisit if the assumptions change: if the application stays single-source and the identifier width
ever shows up in a memory profile, a counter becomes the cheaper answer again. That would be a new
ADR superseding this one.

The consequence to watch: a default-initialised `TLogEvent` has an all-zero identifier, which is a
valid `TGUID` value and not a marker the compiler will reject. Producers go through `New` or `Create`;
an all-zero identifier reaching the table means something built an event by filling in fields instead.
