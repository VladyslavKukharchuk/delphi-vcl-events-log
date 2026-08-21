# 0002. TLogEvent as a value type

- **Status:** accepted
- **Date:** 2026-08-21

## Context

`TLogEvent` is the one type every other unit will touch: the store keeps a collection of them, the
JSON loader produces them, the generator appends them and the form displays them. Its shape has to
be settled before anything holds a collection, because changing it later rewrites every one of those
units.

Forces at play:

- Two writers and one reader are coming. A background thread appends events once a second while the
  form reads the list to paint the table, and importing a file replaces the whole list.
- Standard RTL only, and the application never mutates an event after it is created — an entry in a
  log has no reason to change.
- Delphi has no garbage collector. Whatever shape the entity takes, its lifetime becomes somebody's
  job, and the more hands hold a reference the more places that job can be got wrong.
- There is no persistence layer, no ORM and no inheritance in sight: the type carries four fields
  and no behaviour beyond construction.

## Options

### Option 1 — `record` with read-only properties

A value type. Copying an event copies its fields; the `string` field is reference-counted by the
compiler, so copies are cheap and safe.

- Pro: no lifetime question at all. A snapshot handed to the UI is an independent copy that stays
  valid no matter what the store does next, including replacing everything on import.
- Pro: no `try..finally` per event, no `OwnsObjects`, nothing to free.
- Pro: immutability is expressible — private fields plus read-only properties, set once by the
  constructor.
- Con: copying a collection copies every element. At roughly 40 bytes per event, ten thousand events
  cost about 400 KB per snapshot.
- Con: no polymorphism, and a default-initialised record is a zeroed "empty" event rather than
  something the compiler can reject.

### Option 2 — `class` in a `TObjectList<TLogEvent>` with `OwnsObjects`

The conventional Delphi shape, and the one the repository rules suggest for collections.

- Pro: a snapshot copies pointers, not data — cheap regardless of list size.
- Pro: ownership is explicit and familiar; `OwnsObjects` frees the events with the list.
- Con: the lifetime coupling is the whole problem. Import frees the old objects, and any snapshot the
  UI still holds becomes an array of dangling pointers. It works today because both happen on the
  main thread, and it breaks the first time that stops being true.
- Con: every producer needs a `try..finally` to avoid leaking a half-built event.

### Option 3 — `class` implementing an interface, freed by reference counting

Entities as `ILogEvent`, lifetime managed by the compiler's refcount.

- Pro: cheap snapshots and no manual frees.
- Pro: no dangling pointers — a snapshot keeps its events alive by holding references.
- Con: an interface per entity means a GUID, a declaration and an implementation for a type with
  four fields and no behaviour.
- Con: mixing object and interface references to the same instance is a known way to get a
  double-free, and `[weak]` becomes something every future contributor has to know about.
- Con: pays for polymorphism that nothing in this application needs.

## Decision

Option 1 — `TLogEvent` is a `record` with private fields, read-only properties and a constructor.

Why it won: the property that decides it is that a snapshot must survive whatever the store does
next. With a value type that is true by construction rather than by discipline — the copy the form
holds while painting cannot be invalidated by an import or an append, because it shares nothing with
the store. Options 2 and 3 both buy cheaper snapshots, and neither cost matters at one event per
second.

Option 2 was rejected on the dangling-pointer path specifically. It is safe only as long as every
mutation and every read happen on the same thread, which is an invariant nothing in the code states
and nothing in the compiler checks. Option 3 removes that risk but pays for it with an interface, a
GUID and the object-versus-interface reference trap, for a type that carries four fields.

The accepted cost is copying. If the list ever grew large enough for that to show, the fix is to
snapshot a filtered index rather than the events themselves, which does not change this decision.

The severity level is a plain enumeration, `TEventSeverity = (esInfo, esWarning, esError)`, with a
typed constant array holding the names. Those names serve both the JSON format and the table column,
so the wire format and the display text cannot drift apart.

## Consequences

Easier: passing events around; handing the UI a snapshot; reasoning about what a background thread
can and cannot break. There is no ownership to document because there is none.

Harder: nothing can hold a reference *to* an event and observe changes made elsewhere. That is
deliberate — events do not change — but it means any future "edit an event" feature becomes
replace-in-place rather than mutate-through-a-pointer.

To revisit if the assumptions change: an event gaining behaviour that varies by kind, or lists large
enough for per-snapshot copying to be measurable. Either would call for a new ADR, not an edit here.

The consequence to watch: a `TLogEvent` that nobody constructed is a valid zeroed value with `Id = 0`
and an empty timestamp, and the compiler will not complain about it. Producers go through
`TLogEvent.Create`; code that grows an array should assign constructed values rather than filling in
fields of a default element.
