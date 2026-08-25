# 0002. TLogEvent as a value type

- **Status:** accepted
- **Date:** 2026-08-21

## Context

`TLogEvent` is touched by every layer: the store keeps a collection of them, the JSON loader produces
them, the generator appends them and the form displays them. Its shape has to be settled before
anything holds a collection, because changing it later rewrites all four.

Two things decide it. A background thread appends events once a second while the form reads the list
to paint the table, and importing a file replaces the whole list — so a snapshot handed to the UI
must survive whatever the store does next. And Delphi has no garbage collector: whatever shape the
entity takes, its lifetime becomes somebody's job. The type carries four fields, no behaviour, and is
never mutated after creation.

## Options

### Option 1 — `record` with read-only properties

- Pro: a snapshot is an independent copy that stays valid no matter what the store does next.
- Pro: nothing to free — no `try..finally` per event, no `OwnsObjects`.
- Con: copying a collection copies every element, roughly 40 bytes each.

### Option 2 — `class` in a `TObjectList<TLogEvent>` with `OwnsObjects`

- Pro: a snapshot copies pointers, not data.
- Con: import frees the old objects, and any snapshot the UI still holds becomes dangling pointers.
  It works only while every mutation and every read happen on the same thread — an invariant nothing
  states and nothing checks.

### Option 3 — `class` implementing an interface, freed by reference counting

- Pro: cheap snapshots, no manual frees, no dangling pointers.
- Con: a GUID and an interface declaration for a type with four fields and no behaviour.
- Con: mixing object and interface references to one instance is a known route to a double-free.

## Decision

Option 1 — a `record` with private fields, read-only properties and a constructor.

The deciding property is that a snapshot must survive whatever the store does next, and with a value
type that is true by construction rather than by discipline. Options 2 and 3 both buy cheaper
snapshots, and that cost does not matter at one event per second. Option 2 was rejected specifically
on the dangling-pointer path; Option 3 removes that risk but pays an interface and a GUID for a
four-field type. The accepted cost is copying — if the list ever grew large enough for it to show,
the fix is to snapshot a filtered index rather than the events.

Severity is a plain enumeration, `TEventSeverity = (esInfo, esWarning, esError)`, with a typed
constant array of names shared by the JSON format and the table column, so the two cannot drift.

## Consequences

A `TLogEvent` that nobody constructed is a valid zeroed value — an empty timestamp, and later an
all-zero identifier ([ADR 0003](0003-uuid-event-identifiers.md)) — and the compiler will not complain
about it. Producers go through the constructor; code that grows an array assigns constructed values
rather than filling in fields of a default element.
