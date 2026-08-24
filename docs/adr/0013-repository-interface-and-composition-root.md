# 0013. The repository is an interface, and the object graph is built in the .dpr

- **Status:** accepted
- **Date:** 2026-08-24
- **Supersedes:** the composition paragraph of [ADR 0001](0001-layer-folders-under-src.md); the rest of
  that decision stands

## Context

[ADR 0001](0001-layer-folders-under-src.md) put the object graph in the form: *"the form creates the
store and the generator in `FormCreate` and frees them in `FormDestroy`. That is the composition root;
with a single window there is nothing to extract."* It also rejected interfaces at the layer boundaries,
because *"every interface would have exactly one implementation — indirection paying for nothing."*

Both statements were true when they were written. What changed is what sits below the form.
[ADR 0012](0012-splitting-the-form-into-ui-blocks.md) split the window into blocks and moved the
generator's lifetime into `TGeneratorSession` in `src/Services`, and it closed by naming what it could
not deliver: the session is the only unit above the repository with no `Vcl.*` in it, and therefore the
only one a console test runner can reach — but it takes a concrete `TEventRepository`, so testing it
would mean writing to the user's real database file. ADR 0012 said that seam *"belongs to its own
decision"*. This is that decision.

Forces at play:

- The interface is wanted for one concrete reason: to run the session against a fake that fails on
  demand. "A failed store stops the generator and is reported once" is a rule with three moving parts
  and no way to exercise it by hand — you would have to fill a disk.
- Delphi interfaces are reference counted. This is not a detail that can be deferred: the moment an
  object is reached through an interface, `Free` becomes wrong for it, and mixing the two is a
  double-free rather than a compiler error. Whatever is decided here changes ownership everywhere.
- A form created by `Application.CreateForm` is owned by `Application` and destroyed during unit
  finalisation — *after* the `.dpr` main block has finished. Anything the `.dpr` frees in a `finally` is
  therefore gone before `FormDestroy` runs, and `FormDestroy` stops the generator, which stores an
  event through the repository. Moving composition into the `.dpr` means taking over the form's
  destruction, or crashing on exit.
- Only `src/UI` may show a dialog (ADR 0001). A composition root that fails has to get its reason to
  the window rather than say it itself.
- The assignment asks for none of this. It may not add a feature; it may only move ownership.

## Options

### Where the object graph is built

1. **In `FormCreate`, as ADR 0001 decided.** Pro: one place, and the failure is reported where it has
   to be reported anyway. Pro: `Application.CreateForm` keeps working exactly as anyone opening the
   project expects. Con: the form owns two objects it never asked for, and `src/UI` has to know that a
   repository needs a database — a construction detail of the layer below it. Con: a second window
   would build a second database and open a second connection to the same file.
2. **In the `.dpr`, injected through a method after `CreateForm`.** Pro: one composition root, at the
   entry point, exactly once. Pro: the form holds what it was given and constructs nothing. Con: the
   form gains two phases — `FormCreate` for controls, `Attach` for data — because `FormCreate` runs
   *inside* `CreateForm` and cannot see anything handed over afterwards. Con: the `.dpr` has to free
   the form itself, for the finalisation-order reason above.
3. **In the `.dpr`, injected through the form's constructor.** Pro: the form is never in a half-built
   state. Con: `Application.CreateForm` is what assigns `Application.MainForm`; building the form by
   hand leaves that nil, and then `Application.Run` has no main form to show and closing the window
   does not end the program. Con: what replaces it is hand-written framework plumbing.
4. **A `TDataModule` holding the connection, auto-created by the `.dpr`.** Pro: the traditional Delphi
   answer, with designer support, and creation genuinely at the entry point. Con: a global singleton
   with an implicit dependency, and it puts FireDAC components back into a designer file that ADR 0004
   and ADR 0007 deliberately kept them out of.

### What the seam looks like

1. **No seam; keep the concrete class.** Pro: nothing to explain, no reference counting. Con: the rule
   ADR 0012 could not test stays untested.
2. **`IEventRepository`, in its own unit.** Pro: the contract is separable from the implementation.
   Con: a unit holding six method signatures, and a name that has to be invented for it.
3. **`IEventRepository`, beside its implementation.** Pro: one unit for one responsibility — the stored
   history and how it is reached. Pro: the per-method comments have one home instead of two. Con: a
   consumer that only wants the contract compiles the SQL as well, which in a project of this size
   costs nothing measurable.

### How lifetime works once an interface exists

1. **Reference counting, and the repository owns the database.** Pro: nothing anywhere calls `Free`;
   releasing the last reference takes the database with it. Con: `TEventsDatabase` acquires an owner
   that is reference counted, so the moment its lifetime is destroyed becomes implicit.
2. **Reference counting, database stays a separate object freed by the root.** Pro: the two lifetimes
   stay visible, in one place, in the order they have to happen. Con: one manual `Free` survives, and
   its correctness depends on the order of three lines.
3. **A non-counted interface implementation** (`_AddRef`/`_Release` returning -1). Pro: `Free` keeps
   working, so ownership does not change anywhere. Con: an unusual base class that every reader has to
   be told about, to avoid a language feature rather than to use it.

## Decision

**`IEventRepository` is declared beside `TEventRepository` in
`src/Repository/EventsLog.EventRepository.pas`. `TEventRepository` descends from `TInterfacedObject`
and is reference counted. The database and the repository are created in `EventsLog.dpr`, which is the
composition root; the database stays a separate object that the root frees, and the root also frees the
form, in that order. The window receives the repository through `TMainForm.Attach`.**

Option 2 for the graph, option 3 for the seam, option 2 for lifetime.

The interface won on the strength of exactly one test that could not be written before: a fake
repository that raises on `Insert` shows that the session reports the failure once, stops itself, and
stores nothing. ADR 0001's objection — one implementation, indirection paying for nothing — was right
about production and wrong about the test, and there are now two implementations, one of which lives in
`tests/`.

The database stays a separate object because the alternative hides the more dangerous of the two
lifetimes. A repository that owned the database would release it whenever its own last reference went,
and *which* reference is last would depend on the order in which the form, the actions block and the
session let go. Keeping it separate puts all three steps in one `finally`, in writing:

```pascal
finally
  FreeAndNil(MainForm);
  Repository := nil;
  Database.Free;
end;
```

Those three lines are the whole of the decision and each one is load-bearing. `FreeAndNil(MainForm)` is
first because an auto-created form would otherwise be destroyed during unit finalisation, long after
this block: `FormDestroy` stops the generator, stopping the generator stores whatever it had in flight,
and storing needs a repository and a database that would both already be gone. Freeing the form here
puts its destructor back in front of ours, and `TControl.Destroy` calls
`TApplication.ControlDestroyed`, which clears `Application.MainForm` — so nothing is left dangling.
`Repository := nil` then drops the last reference, and only then is the database it was reading from
freed.

Two phases in the form is the cost paid for this. `FormCreate` builds the controls and the blocks;
`Attach` receives the repository, builds the actions block and paints the window for the first time.
A nil repository is how `Attach` learns there is no database, and `AProblem` is the reason — because
the root may not open a dialog, and the window may.

## Consequences

Easier: the session's rules are under test, and adding a test for anything else above the repository
now costs a fake and nothing else. The form constructs nothing, so `src/UI` no longer names
`TEventsDatabase` at all — `EventsLog.Database` left its `uses` clause. A second window becomes
possible without a second connection, which was the concrete failure ADR 0001 left open.

Harder: ownership is no longer uniform. Most objects here are freed by whoever created them; a
repository is not freed at all, and a `Free` added next to an interface reference is a double-free that
compiles cleanly. The three-line `finally` in the `.dpr` is the other half of the same hazard — it
reads like tidy-up and is actually the shutdown order of the whole application.

What to watch: the tests pump `CheckSynchronize` themselves, because `TThread.Queue` only delivers when
somebody does and a console runner has no message loop. That is written down in the test unit, but it
is the first thing that will confuse whoever adds the next threading test. The session's interval is a
constructor parameter for the same reason — so a test does not wait out a real second — and production
never passes it.

Not delivered: `TEventRepository` itself is still only reachable against a real database file, so the
SQL — the `where` clause, the severity macro, the query limit — remains untested. That needs
`TEventsDatabase` to accept a path instead of always resolving one under `%APPDATA%` (ADR 0005), which
is a change to a different unit and its own decision. `TEventTable`, `TFilterPanel` and `TEventActions`
hold VCL controls and are no more testable than before; ADR 0012 said so and this does not change it.

To revisit if the assumptions change: a second window, which is now possible and would make `Attach`
into a pattern rather than a one-off; a test project that needs the real repository, which is the
argument for an injectable database path; or a third implementation of `IEventRepository` — a remote
one, say — which is the point at which putting the contract in its own unit would start to pay.
