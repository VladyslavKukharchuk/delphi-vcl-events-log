# 0001. Layer folders under src/ with plain classes

- **Status:** accepted; the composition paragraph is superseded by [0013](0013-repository-interface-and-composition-root.md)
- **Date:** 2026-08-21

## Context

The application holds events in memory, filters them, loads them from JSON, generates them on a
background thread and shows them in a table — five distinct responsibilities. The structure has to be
settled before the first unit is written, because moving units later means touching the `.dpr`, the
`.dproj` and the search path together.

- Standard RTL/VCL only: no Spring4D, no tiOPF, no DI container.
- Delphi has no module system. A "layer" exists only as a folder, a naming convention and a `uses`
  discipline — but the compiler does reject cyclic `interface` sections, so dependency direction is
  verifiable by building.
- The statement asks for no unit tests, so testability alone cannot justify extra indirection.

The form-centric default — list, JSON parsing and generator all inside `Main.pas` — is out from the
start: it puts guarded parsing and a background writer inside event handlers, which is where those
defects survive review.

## Options

### Option 1 — flat units by responsibility in the project root

- Pro: zero project configuration — no search path, no relative paths in the `.dpr`.
- Con: the root mixes code with `.dproj`, `README.md`, sample JSON and `docs/`.
- Con: the layer of a unit is a matter of reading its name and then its `uses` clause.

### Option 2 — layer folders under `src/`, plain classes

`src/Model`, `src/Repository`, `src/Services`, `src/UI`. Short unit names; the folder carries the
layer. One-way `uses`, no interfaces at the boundaries.

- Pro: the shape of the application is visible in the file tree.
- Pro: the rule is mechanically checkable — no `Vcl.` under `src/Model`, `src/Repository` or
  `src/Services`.
- Con: needs relative paths in the `.dpr` and the folders in `DCC_UnitSearchPath`.
- Con: no interface seams, so a unit cannot be substituted in a test without touching its consumer.

### Option 3 — layer folders plus ports, adapters and MVP

Option 2 plus `IEventRepository`, `IEventsView`, a presenter and a composition root in the `.dpr`.

- Pro: makes the filtering logic and the loader testable without a form.
- Con: every interface would have exactly one implementation.
- Con: a passive view means hand-wiring every control — VCL has no usable declarative binding.
- Con: forms must leave auto-create to be built by a composition root, which fights the IDE.

## Decision

Option 2 — layer folders under `src/`, plain classes, one-way `uses`.

```
EventsLog.dpr      entry point and composition root
src/Model/         EventsLog.Event.pas, EventsLog.Store.pas, EventsLog.Filter.pas
src/Repository/    EventsLog.Json.pas
src/Services/      EventsLog.Generator.pas
src/UI/            Main.pas / .dfm
```

It won over Option 1 because both give the same dependency direction but only folders make it
visible, and the cost is one-off while the benefit is paid every time someone opens the project. It
won over Option 3 on proportion rather than principle: the folders are cheap, the seams are not, and
the seams buy tests the statement does not ask for.

Ownership is plain — the form creates the store and the generator in `FormCreate` and frees them in
`FormDestroy`. With a single window there is nothing to extract.

## Consequences

Folders document the layering but do not enforce it. Nothing in the compiler stops `src/Model` from
reaching for the UI, only the one-way `uses` discipline: pull requests check that nothing outside
`src/UI` carries `Vcl.*` or a message dialog. Adding a unit is also no longer one step — right
folder, `.dpr` with a relative path, and `DCC_UnitSearchPath` for a new layer — and the IDE defaults
to the project root when saving.
