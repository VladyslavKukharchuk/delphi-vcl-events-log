# 0013. The repository is an interface, and the object graph is built in the .dpr

- **Status:** accepted
- **Date:** 2026-08-24
- **Supersedes:** the composition paragraph of [ADR 0001](0001-layer-folders-under-src.md); the rest of
  that decision stands

## Context

[ADR 0001](0001-layer-folders-under-src.md) put the object graph in the form and rejected interfaces
at the layer boundaries, because "every interface would have exactly one implementation". Both
statements were true when written. What changed is what sits below the form:
[ADR 0012](0012-splitting-the-form-into-ui-blocks.md) moved the generator's lifetime into
`TGeneratorSession` in `src/Services` and closed by naming what it could not deliver — the session is
the only unit above the repository with no `Vcl.*` in it, and therefore the only one a console test
runner can reach, but it takes a concrete `TEventRepository`. This is that decision.

- The interface is wanted for one concrete reason: to run the session against a fake that fails on
  demand. "A failed store stops the generator and is reported once" is a rule with three moving parts
  and no way to exercise it by hand — you would have to fill a disk.
- Delphi interfaces are reference counted, and this cannot be deferred: the moment an object is
  reached through an interface, `Free` becomes wrong for it, and mixing the two is a double-free
  rather than a compiler error.
- A form created by `Application.CreateForm` is destroyed during unit finalisation — *after* the
  `.dpr` main block has finished. Anything the `.dpr` frees in a `finally` is gone before
  `FormDestroy` runs, and `FormDestroy` stops the generator, which stores an event through the
  repository.
- Only `src/UI` may show a dialog (ADR 0001), so a composition root that fails has to get its reason
  to the window rather than say it itself.

## Options

### Where the object graph is built

1. **In `FormCreate`, as ADR 0001 decided.** Pro: one place, and the failure is reported where it has
   to be reported anyway. Con: the form owns two objects it never asked for, and `src/UI` has to know
   that a repository needs a database. Con: a second window would open a second connection.
2. **In the `.dpr`, injected through a method after `CreateForm`.** Pro: one composition root, at the
   entry point, exactly once; the form constructs nothing. Con: the form gains two phases, because
   `FormCreate` runs *inside* `CreateForm` and cannot see anything handed over afterwards. Con: the
   `.dpr` has to free the form itself.
3. **In the `.dpr`, injected through the form's constructor.** Pro: the form is never half-built. Con:
   `Application.CreateForm` is what assigns `Application.MainForm`; building the form by hand leaves
   that nil, and then closing the window does not end the program.
4. **A `TDataModule` holding the connection.** Pro: the traditional Delphi answer, with designer
   support. Con: a global singleton with an implicit dependency, and it puts FireDAC components back
   into a designer file that ADR 0004 and ADR 0007 deliberately kept them out of.

### What the seam looks like

1. **No seam; keep the concrete class.** Con: the rule ADR 0012 could not test stays untested.
2. **`IEventRepository` in its own unit.** Pro: the contract is separable. Con: a unit holding six
   method signatures, and a name to invent for it.
3. **`IEventRepository` beside its implementation.** Pro: one unit for one responsibility — the
   stored history and how it is reached. Con: a consumer that only wants the contract compiles the
   SQL as well.

### How lifetime works once an interface exists

1. **Reference counting, repository owns the database.** Pro: nothing calls `Free`. Con: the moment
   the database dies becomes implicit.
2. **Reference counting, database freed by the root.** Pro: both lifetimes stay visible, in one
   place, in the order they have to happen. Con: one manual `Free` survives.
3. **A non-counted implementation** (`_AddRef`/`_Release` returning -1). Pro: `Free` keeps working.
   Con: an unusual base class every reader has to be told about, to avoid a language feature rather
   than use it.

## Decision

**`IEventRepository` is declared beside `TEventRepository`. `TEventRepository` descends from
`TInterfacedObject` and is reference counted. The database and the repository are created in
`EventsLog.dpr`, which is the composition root; the database stays a separate object that the root
frees, and the root also frees the form, in that order. The window receives the repository through
`TMainForm.Attach`.**

The interface won on the strength of exactly one test that could not be written before: a fake
repository that raises on `Insert` shows that the session reports the failure once, stops itself, and
stores nothing. ADR 0001's objection was right about production and wrong about the test — there are
now two implementations, one of which lives in `tests/`.

The database stays separate because the alternative hides the more dangerous of the two lifetimes: a
repository that owned it would release it whenever its own last reference went, and *which* reference
is last would depend on the order in which the form, the actions block and the session let go.
Keeping it separate puts all three steps in one `finally`, in writing:

```pascal
finally
  FreeAndNil(MainForm);
  Repository := nil;
  Database.Free;
end;
```

Each line is load-bearing. `FreeAndNil(MainForm)` is first because an auto-created form would
otherwise be destroyed during unit finalisation, long after this block — and `FormDestroy` stops the
generator, which stores through a repository that would already be gone. Freeing it here puts its
destructor back in front of ours, and `TControl.Destroy` clears `Application.MainForm`, so nothing is
left dangling. `Repository := nil` then drops the last reference, and only then is the database freed.

Two phases in the form is the cost paid for this: `FormCreate` builds the controls and the blocks;
`Attach` receives the repository and paints the window for the first time. A nil repository is how
`Attach` learns there is no database, because the root may not open a dialog and the window may.

## Consequences

Ownership is no longer uniform. Most objects here are freed by whoever created them; a repository is
not freed at all, and a `Free` added next to an interface reference is a double-free that compiles
cleanly. The three-line `finally` reads like tidy-up and is actually the shutdown order of the whole
application.

The tests pump `CheckSynchronize` themselves, because `TThread.Queue` only delivers when somebody
does and a console runner has no message loop. The session's interval is a constructor parameter for
the same reason — so a test does not wait out a real second — and production never passes it.

Still not testable: `TEventRepository` itself, which is only reachable against a real database file,
so the SQL remains untested. That needs `TDatabase` to accept a path instead of always
resolving one under `%LOCALAPPDATA%` (ADR 0005), which is its own decision.
