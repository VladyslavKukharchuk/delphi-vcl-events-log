# 0001. Layer folders under src/ with plain classes

- **Status:** accepted
- **Date:** 2026-08-21

## Context

The application has to hold events in memory, filter them, load them from JSON, generate them on a
background thread and show them in a table. That is five distinct responsibilities, and the code
structure has to be settled before the first unit is written, because moving units later means
touching the `.dpr`, the `.dproj` and the search path together.

Forces at play:

- Standard RTL/VCL only — no Spring4D, no tiOPF, no DI container is available to us.
- The statement asks for no unit tests, so testability alone cannot justify extra indirection.
- Delphi has no module system and no package-private visibility. The unit is the encapsulation
  boundary: whatever sits in `implementation` is invisible from outside. A "layer" therefore exists
  only as a folder, a naming convention and a `uses` discipline.
- Delphi does enforce one architectural rule for free: two units may not reference each other from
  their `interface` sections — the compiler rejects the cycle. Dependency direction is verifiable by
  building the project.
- The developer on this task comes from backend work with layered clean architecture and wants the
  structure to be navigable in those terms. That is a legitimate force: a structure nobody can find
  their way around costs more than it saves.

## Options

### Option 1 — form-centric, everything in `Main.pas`

The default RAD approach: the form owns the list, parses the JSON in a button handler, runs the
generator and updates the controls.

- Pro: the least code, and idiomatic for a large share of existing Delphi applications.
- Con: the JSON loader and the generator become untestable and unreadable, tangled with control
  access.
- Con: guarding a list against a background thread inside form event handlers is where threading
  bugs hide.
- Con: contradicts the working rules of this repository, which require one unit per responsibility.

### Option 2 — flat units by responsibility in the project root

One unit per responsibility, all next to the `.dpr`, with the layer implied by the unit name only.

- Pro: zero project configuration — no search path, no relative paths in the `.dpr`.
- Pro: the most common layout in small Delphi projects.
- Con: the root directory mixes code with `.dproj`, `README.md`, sample JSON and `docs/`; at a dozen
  files it stops being scannable.
- Con: the layer of a unit is a matter of reading its name and then its `uses` clause. Nothing shows
  the shape of the project at a glance.

### Option 3 — layer folders under `src/`, plain classes

`src/Model`, `src/Repository`, `src/Services`, `src/UI`. Units stay ordinary classes with short names;
the folder carries the layer. Dependencies point one way, enforced by review plus the compiler's ban
on cyclic `interface` sections. No interfaces at the boundaries, no presenter, no container.

- Pro: the shape of the application is visible in the file tree, in the vocabulary the developer
  already thinks in.
- Pro: keeps the property that matters from a layered design — the domain depends on nothing.
- Pro: the rule is mechanically checkable: no `Vcl.` in the `uses` clause of anything under
  `src/Model`, `src/Repository` or `src/Services`.
- Con: needs project configuration — relative paths in the `.dpr` and the folders listed in
  `DCC_UnitSearchPath`; a unit added through the IDE in the wrong folder is easy to miss.
- Con: four folders for six units is more structure than a Delphi reviewer would expect at this
  size.
- Con: no interface seams, so a unit cannot be substituted in a test without touching its consumer.

### Option 4 — layer folders plus ports, adapters and MVP

Option 3, plus boundaries declared as interfaces (`IEventRepository`, `IEventsView`), a presenter
driving a passive form, and a composition root wiring everything in the `.dpr`.

- Pro: the structure a backend developer coming from clean architecture expects in full.
- Pro: makes the filtering logic and the loader testable without a form.
- Con: every interface would have exactly one implementation — indirection paying for nothing.
- Con: a passive view means hand-wiring every control, because VCL has no usable declarative data
  binding; LiveBindings is the only option and it is slow and awkward.
- Con: forms must be taken out of auto-create to be built by a composition root, which fights the
  IDE and surprises anyone opening the project.

## Decision

Option 3 — layer folders under `src/`, plain classes, one-way `uses`.

Why it won over Option 2: both give the same dependency direction, but only the folders make it
visible. The cost is one-off — relative paths in the `.dpr` and one search path entry — while the
benefit is paid out every time someone opens the project. Navigability was treated as a real
requirement here, not a preference, because the alternative is a root directory where code and
project furniture sit side by side.

Why it won over Option 4: the ports and adapters were rejected on proportion rather than on
principle. Every interface they introduce would have a single implementation, and the passive view
they require costs real hand-wiring in VCL while buying tests the statement does not ask for. The
folders are cheap; the seams are not.

Option 1 was rejected because it puts the two genuinely tricky parts — guarded JSON parsing and a
background writer to a shared list — inside event handlers, which is where those defects survive
review.

Concretely:

```
EventsLog.dpr      entry point and composition root
src/Model/         EventsLog.Event.pas, EventsLog.Store.pas, EventsLog.Filter.pas
src/Repository/    EventsLog.Json.pas
src/Services/      EventsLog.Generator.pas
src/UI/            Main.pas / .dfm
```

Unit names stay short: the folder carries the layer, the name carries the role. Ownership is plain —
the form creates the store and the generator in `FormCreate` and frees them in `FormDestroy`. That
is the composition root; with a single window there is nothing to extract.

## Consequences

Easier: seeing what the application is made of; moving the generator or the loader elsewhere;
reasoning about which code may touch controls.

Harder: adding a unit is no longer a single step — it goes in the right folder, into the `.dpr` with
a relative path, and its folder into `DCC_UnitSearchPath` if it is a new layer. The IDE defaults to
the project root when saving a new unit, so this is easy to get wrong.

Also harder: unit-testing the filtering logic or the loader in isolation, since neither sits behind
an interface. If tests were added later, the loader would be the first thing to gain a seam — it is
already a pure function from file contents to events plus a report.

To revisit if the assumptions change: should this grow past a single window, the form would take on
presentation logic that belongs in a presenter, and Option 4 becomes worth its cost. That would be a
new ADR superseding this one, not an edit here.

The consequence to watch: folders document the layering but do not enforce it. Nothing in the
compiler stops `src/Model` from reaching for the UI, only the one-way `uses` discipline. Pull
requests check that nothing outside `src/UI` carries `Vcl.*` or a message dialog — errors travel out
as results or exceptions, and only the form turns them into something a user sees.
