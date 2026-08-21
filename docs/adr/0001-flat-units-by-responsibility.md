# 0001. Flat units by responsibility instead of a layered architecture

- **Status:** accepted
- **Date:** 2026-08-21

## Context

The application has to hold events in memory, load them from JSON, generate them on a background
thread and show them in a table. That is four distinct responsibilities, and the statement asks for
a small program rather than a framework.

Forces at play:

- Standard RTL/VCL only — no Spring4D, no tiOPF, no DI container is available to us.
- The statement asks for no unit tests, so testability cannot be used to justify extra indirection.
- A reviewer reads this codebase in a few minutes and judges whether the structure fits the size of
  the task. Both "everything in the form" and "ports, adapters and a composition root for four
  units" read badly.
- Delphi enforces one architectural rule for free: two units may not reference each other from
  their `interface` sections — the compiler rejects the cycle. Dependency direction is therefore
  verifiable by building the project, not by convention alone.
- Delphi has no module system and no package-private visibility. The unit *is* the encapsulation
  boundary: whatever sits in `implementation` is invisible from outside.

## Options

### Option 1 — form-centric, everything in `Main.pas`

The default RAD approach: the form owns the list, parses the JSON in a button handler, runs the
generator and updates the controls.

- Pro: the least code, and idiomatic for a large share of existing Delphi applications.
- Pro: nothing to navigate — one file.
- Con: the JSON loader and the generator become untestable and unreadable, because they are tangled
  with control access.
- Con: guarding a list against a background thread inside form event handlers is where threading
  bugs hide.
- Con: contradicts the working rules of this repository, which require one unit per responsibility.

### Option 2 — flat units by responsibility

One unit per responsibility, all in the project root, with dotted unit scope names. Dependencies
point one way: the form knows every unit, no unit knows the form.

```
EventsLog.Model.pas       entities and the store   — knows about neither VCL nor JSON
EventsLog.Json.pas        file adapter             — knows Model and System.JSON
EventsLog.Generator.pas   background service       — knows Model and TThread
Main.pas                  UI and composition       — knows all of them
```

- Pro: the same dependency direction as a layered design — inwards only, domain at the centre.
- Pro: the rule is mechanically checkable: `EventsLog.Model.pas` must contain no `Vcl.` in its
  `uses` clause.
- Pro: sized to the task; a reviewer sees the responsibilities at a glance in the Project Manager.
- Con: no interface seams, so a unit cannot be substituted in a test without touching its consumer.
- Con: nothing stops a future contributor from putting a `ShowMessage` in `EventsLog.Json.pas` —
  only review catches that.

### Option 3 — layered folders with ports, adapters and MVP

Subfolders per layer (`Domain`, `Application`, `Infrastructure`, `Presentation`), boundaries
declared as interfaces (`IEventRepository`, `IEventsView`), a presenter driving a passive form, and
a composition root wiring it all in the `.dpr`.

- Pro: the structure a backend developer coming from clean architecture expects to find.
- Pro: makes the filtering logic and the loader testable without a form.
- Con: an interface per boundary for a store that is one in-memory list, with a single
  implementation each, is indirection paying for nothing.
- Con: a passive view means hand-wiring every control, because VCL has no usable declarative data
  binding — LiveBindings is the only option and it is slow and awkward.
- Con: forms must be removed from auto-create to be constructed by a composition root, which fights
  the IDE and surprises anyone opening the project.
- Con: roughly doubles the file count for an application whose entire domain is one record type.

## Decision

Option 2 — flat units by responsibility.

Why it won: it keeps the property that actually matters from a layered design — a domain that
depends on nothing, with dependencies pointing one way — and drops the machinery that only pays off
at a larger scale. The dependency direction is not a documented intention here but a build-time
constraint, because Delphi refuses cyclic `interface` sections; and the "domain knows nothing about
the UI" rule reduces to a grep over one `uses` clause.

Option 3 was rejected on proportion rather than on principle. Every interface it introduces would
have exactly one implementation, and the passive view it requires costs real hand-wiring in VCL
while buying tests the statement does not ask for. Option 1 was rejected because it puts the two
genuinely tricky parts — guarded JSON parsing and a background writer to a shared list — inside
event handlers, which is where those defects survive review.

## Consequences

Easier: reading the project; moving the generator or the loader elsewhere; reasoning about which
code may touch controls.

Harder: unit-testing the filtering logic or the loader in isolation, since neither sits behind an
interface. If tests were added later, the loader would be the first thing to gain a seam — it is
already a pure function from file contents to events plus a report.

To revisit if the assumptions change: should this grow past a single window, the form would take on
presentation logic that belongs in a presenter, and Option 3 becomes worth its cost. That would be
a new ADR superseding this one, not an edit here.

The consequence to watch: the flat layout has no compiler-enforced ban on a unit reaching for the
UI, only the one-way `uses` discipline. Pull requests need to check that `EventsLog.Model.pas`,
`EventsLog.Json.pas` and `EventsLog.Generator.pas` stay free of `Vcl.*` and of message dialogs —
errors travel out as results or exceptions, and only `Main.pas` turns them into something a user
sees.
