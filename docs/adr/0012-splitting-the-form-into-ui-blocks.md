# 0012. The form is split into blocks that drive the controls it owns

- **Status:** accepted
- **Date:** 2026-08-24

## Context

`src/UI/Main.pas` had grown to 336 lines, of which about 260 were code. The business logic was
already out of it (ADR 0001), so what had accumulated was UI logic — and six jobs were sharing one
class: creating the repository and degrading the window when that fails; the generator's lifetime;
the search box and severity list; the table and the line under it; importing a file; clearing the
history.

Two of those carried all the difficulty. The generator's callback runs on the main thread but inside
a queue belonging to the generator's thread, so it may neither free that thread nor open a modal
dialog ([ADR 0011](0011-event-generator-thread.md)); the table is virtual, so the form also owned the
array behind it. None of that was visible from outside — a reader had to hold six jobs in their head
to follow any one of them.

- `src/UI` is the only place allowed to touch `Vcl.*` or show a dialog. All three visible blocks are
  made of controls, so all three stay in `src/UI` whatever shape they take. Only the generator's
  lifetime has nothing to do with controls, and only it can leave the layer.
- The window is one `.dfm`. A reviewer opens the designer once and expects to see the whole layout.
- The tests are a DUnitX console application. A class holding VCL controls is awkward to instantiate
  there, so splitting the form does not by itself make its logic testable — worth being honest about
  rather than claiming as a benefit.
- The assignment asks for none of this. Nothing here may add a feature or a screen; it may only move
  existing code.

## Options

### How the form is divided

1. **Leave it as one form.** Pro: no new files, and everything about the window is in one place. Con:
   the six jobs stay interleaved, and the two hard ones stay hidden among the four easy ones.
2. **A `TFrame` per visual block.** Pro: the frame owns its controls, so encapsulation is enforced by
   the language rather than by discipline; it is the idiomatic Delphi answer. Con: each frame would
   be used exactly once, so the reuse is never collected. Con: the layout splits across four `.dfm`
   files, each a new source of the designer noise this repository already has to police.
3. **Plain classes in `src/UI`, driving controls the form still owns.** Pro: the layout stays in one
   `.dfm`, no new file is IDE-generated, and each block is an ordinary unit. Con: ownership is split
   — the block drives controls it must not free, and nothing but a comment says so.
4. **A full presenter (MVP).** Pro: the only option here that is genuinely testable without a window.
   Con: an interface, a presenter and a view-per-window for an application with one window; the diff
   stops being reviewable as a refactoring.

### Where the generator's lifetime lives

1. **In the form, as before.** Con: the three fields that make it work sit among the form's controls,
   and the reason each exists is a comment rather than a boundary.
2. **In a session class in `src/Services`.** Pro: the only part of the form with a genuine
   concurrency argument becomes the only part with no `Vcl.*` in it. Con: the timer cannot go with it
   — `TTimer` is `Vcl.ExtCtrls` — so the session answers questions instead of asking them.

### Who refreshes the table, and who shows dialogs

Either each block refreshes the table itself — which means every block needs a reference to it, and
the import knows about the status bar — or a block says the history changed and the form refreshes.
Dialogs likewise: all in the form, which then has to be handed the import report to say anything
about it, or each where the knowledge is.

## Decision

**The form is split into three plain classes in `src/UI` — `TEventTable`, `TFilterPanel`,
`TEventActions` — each driving controls the form continues to own, plus `TGeneratorSession` in
`src/Services` for the generator's lifetime. Blocks report that the history changed; the form is the
only thing that refreshes. Dialogs live with the knowledge, except the generator's failure, which the
form shows.**

Option 3 won over frames because the reuse that would justify a frame does not exist: every block is
used once, and the price — a layout spread over four designer files — is paid immediately and
forever. It won over MVP because MVP buys testability the console test project cannot collect anyway
without also putting the repository behind an interface, which is a change to a different layer.

The split ownership is the cost we accepted. It is stated in the header comment of each block, and it
is the one thing a reader has to be told rather than shown: the controls belong to the form, and a
block that freed one would take a control out from under the window still using it.

The session is the piece that pays for itself. `TakeStale` and `TakeProblem` exist because a callback
running inside the generator's own queue can neither free that thread nor open a modal dialog; moving
them into a class with no `Vcl.*` makes that argument the subject of a file instead of a comment in a
form. The form keeps the timer, and with it the one dialog that could not move — taking the problem
stops the session, but the timer is disabled by the form reading the session's state, so the dialog
has to come after that read. `TEventActions.Poll` therefore returns the message rather than showing
it.

`ViewRefreshed` closes the loop: a refresh caused by an import or a keystroke has also shown whatever
the generator produced, so the form tells the actions block the flag has been answered. Without it,
typing in the search box while generating would run every query twice.

## Consequences

The destruction order is load-bearing. The actions are freed first because that stops the generator,
and a generated event still in flight is stored on this thread and would otherwise reach a repository
that is gone. The blocks also hold controls they do not own: nothing but a comment prevents a `Free`
in the wrong destructor, and the symptom would be a window that crashes on close rather than a
compiler error.

Not delivered by this decision: tests. `TGeneratorSession` is now the only piece with no `Vcl.*`, but
it takes a concrete `TEventRepository`, so testing it would write to the real database. That
interface belongs to its own decision ([ADR 0013](0013-repository-interface-and-composition-root.md));
until then this refactoring buys legibility and not coverage.
