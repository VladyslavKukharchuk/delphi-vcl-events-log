# 0012. The form is split into blocks that drive the controls it owns

- **Status:** accepted
- **Date:** 2026-08-24

## Context

`src/UI/Main.pas` had grown to 336 lines, of which about 260 were code. The business logic was already
out of it — the model, the repository, the JSON import and the generator each live in their own layer
([ADR 0001](0001-layer-folders-under-src.md)) — so what had accumulated in the form was UI logic, and
six separate jobs were sharing one class:

1. creating the database and the repository, and degrading the window when that fails,
2. the generator's lifetime, and delivering the failures its callback cannot report itself,
3. the search box and the severity list,
4. the table and the line under it,
5. importing a JSON file and reporting what came of it,
6. clearing the history.

Jobs 2 and 4 carried all the difficulty. The generator's callback runs on the main thread but inside a
queue belonging to the generator's thread, so it may neither free that thread nor open a modal dialog
([ADR 0011](0011-event-generator-thread.md)); the table is virtual, so the form also owned the array
behind it and the sentence explaining that the query is capped. None of that was visible from the
outside: a reader had to hold six jobs in their head to follow any one of them.

Forces at play:

- `src/UI` is the only place allowed to touch `Vcl.*` or show a dialog (ADR 0001). All three of the
  visible blocks are made of controls, so all three stay in `src/UI` whatever shape they take. Only the
  generator's lifetime has nothing to do with controls, and only it can leave the layer.
- The window is one `.dfm`. A reviewer opens the designer once and expects to see the whole layout;
  anything that moves controls out of that file is paid for in review time.
- There is no command-line build in this edition, so every option costs an IDE round trip to try. This
  argues for the shape with the fewest new moving parts, not the most fashionable one.
- The tests are a DUnitX console application. A class holding VCL controls is awkward to instantiate
  there, so splitting the form does not by itself make the form's logic testable — a point worth being
  honest about rather than claiming as a benefit.
- The assignment does not ask for any of this. Nothing here may add a feature or a screen; it may only
  move existing code.

## Options

### How the form is divided

1. **Leave it as one form.** Pro: no new files, and 260 lines is not a crisis. Pro: everything about
   the window is in one place, which is the shape most Delphi reviewers expect. Con: the six jobs stay
   interleaved, and the two hard ones stay hidden among the four easy ones.
2. **A `TFrame` per visual block.** Each block becomes a real component with its own `.pas` and `.dfm`,
   dropped onto the form in the designer. Pro: the frame owns its controls, so encapsulation is
   enforced by the language rather than by discipline. Pro: it is the idiomatic Delphi answer to "make
   this reusable". Con: each frame would be used exactly once, so the reuse is never collected. Con: the
   layout splits across four `.dfm` files and can no longer be read at a glance. Con: the IDE writes
   those files, so each one is a new source of the designer noise this repository already has to police.
3. **Plain classes in `src/UI`, each driving controls the form still owns.** The form creates a block
   and hands it the controls it is responsible for. Pro: the layout stays in one `.dfm`, and no new file
   is IDE-generated. Pro: each block is an ordinary unit — readable, greppable, and cheap to move later.
   Con: ownership is split. The block drives controls it must not free, and nothing but a comment says
   so. Con: the dependency is invisible in the designer; it exists only in `FormCreate`.
4. **A full presenter (MVP).** The form becomes a passive view behind an interface, and a presenter
   holds every decision. Pro: the presenter is testable without a window, which is the only option here
   that genuinely is. Con: an interface, a presenter and a view-per-window for an application with one
   window — the machinery is larger than the thing it organises, and the diff stops being reviewable as
   a refactoring.

### Where the generator's lifetime lives

1. **In the form, as before.** Con: the three fields that make it work — the thread, "something
   arrived", "storing failed" — sit among the form's controls, and the reason each exists is a comment
   rather than a boundary.
2. **In a session class in `src/Services`.** Pro: the only part of the form with a genuine concurrency
   argument becomes the only part with no `Vcl.*` in it, which is also the only part that could ever be
   put under test. Con: the timer cannot go with it — `TTimer` is `Vcl.ExtCtrls` — so the session ends
   up answering questions instead of asking them, and the form keeps the timer that asks.

### Who refreshes the table

1. **Each block refreshes it itself.** Con: every block then needs a reference to the table, and the
   import knows about the status bar. The blocks stop being independent and the form stops being the
   thing that connects them.
2. **A block says the history changed; the form refreshes.** Pro: one path back to the screen, no
   matter what changed it — import, clear, an arriving generated event, or a new filter. Pro: the
   actions block does not know the table exists. Con: the "new events are waiting" flag then lives in
   the session while the refresh happens in the form, so a refresh for any other reason has to say it
   happened, or the next timer tick repeats it.

### Who shows dialogs

1. **All of them in the form.** Pro: one place to look for anything the user is told. Con: the form has
   to be handed the import report and the delete count to say anything about them, so the knowledge and
   the sentence live in different files.
2. **Each dialog where the knowledge is.** Pro: the code that knows what happened is the code that says
   it. Con: dialogs are then in two files rather than one, and one of them — the generator's failure —
   cannot follow the rule, because it must be shown only after the timer is off.

## Decision

**The form is split into three plain classes in `src/UI` — `TEventTable`, `TFilterPanel`,
`TEventActions` — each driving controls the form continues to own, plus `TGeneratorSession` in
`src/Services` for the generator's lifetime. Blocks report that the history changed; the form is the
only thing that refreshes. Dialogs live with the knowledge, except the generator's failure, which the
form shows.**

Option 3 won over the frames because the reuse that would justify a frame does not exist: every block is
used once, and the price — a layout spread over four designer files, each a new place for the IDE to
inject noise — is paid immediately and forever. It won over MVP because MVP buys testability that the
console test project cannot collect anyway without also putting the repository behind an interface,
which is a change to a different layer and not this one.

The split ownership that comes with option 3 is the cost we accepted. It is stated in the header comment
of each block, and it is the one thing a reader has to be told rather than shown: the controls belong to
the form, which got them from its `.dfm`, and a block that freed one would take a control out from under
the window that is still using it.

The session is the piece that pays for itself. `TakeStale` and `TakeProblem` exist because a callback
running inside the generator's own queue can neither free that thread nor open a modal dialog; moving
them into a class with no `Vcl.*` makes that argument the subject of a file instead of a comment in a
form. The session stops itself when its problem is taken, since the next insert would fail the same way.

The form keeps the timer, and with it the one dialog that could not move: taking the problem stops the
session, but the timer is disabled by the form reading the session's state, so the dialog has to come
after that read. `TEventActions.Poll` therefore returns the message rather than showing it — the only
place in this design where a block hands a sentence out instead of saying it.

`ViewRefreshed` is the answer to the last con above. A refresh caused by an import or a keystroke in the
search box has also shown whatever the generator had produced, so the form tells the actions block that
the flag has been answered. Without it, typing in the search box while generating would run every query
twice.

## Consequences

Easier: reading any one job. The status bar's four cases are the only thing in
`EventsLog.EventTable.pas`; the severity list is the only thing in `EventsLog.FilterPanel.pas`; the form
is 178 lines in which every handler is one line, so what the window does is a list rather than a search.
Moving a block later — into a frame, or behind a presenter — is now a change to one file instead of an
extraction from six.

Harder: the wiring is real, and it is only in `FormCreate` and `FormDestroy`. The destruction order is
load-bearing — the actions are freed first because that stops the generator, and a generated event still
in flight is stored on this thread and would otherwise reach a repository that is gone. That was true
before and it is still true; it has simply moved one level out.

What to watch: the blocks hold controls they do not own. Nothing but a comment prevents a `Free` in the
wrong destructor, and the symptom would be a window that crashes on close rather than a compiler error.

Not delivered by this decision: tests. `TGeneratorSession` is now the only piece with no `Vcl.*`, so it
is the only one that could be tested — but it takes a concrete `TEventRepository`, and testing it would
either write to the real database or require the repository behind an interface. That interface is a
change to `src/Repository` and belongs to its own decision; until then this refactoring buys legibility
and not coverage, and `README.md` should say so among the things more time would improve.

To revisit if the assumptions change: a second window, which would make `TFilterPanel` and
`TEventTable` worth their `.dfm` files after all and turn option 2 from cost into value; a requirement
to test the window's logic, which is the argument for option 4 and for the repository interface at the
same time; or a filter expensive enough to need debouncing, which would put a second timer in the form
and is the first thing that would make the single refresh path here too simple.
