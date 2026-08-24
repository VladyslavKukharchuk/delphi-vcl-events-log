# 0014. Rejected records get their own window, listed in full

- **Status:** accepted
- **Date:** 2026-08-24
- **Revises:** the reporting half of [ADR 0009](0009-json-import-semantics.md), which kept only the
  first problem

## Context

ADR 0009 settled what happens to a record that cannot be read: it is skipped rather than failing the
whole import, and something is said about it afterwards. What it said was deliberately thin — a count
and the text of the *first* problem, both carried by `TImportReport` and shown in the same
`MessageDlg` as the success line. Its own "to revisit" list named the obvious successor: reporting
every problem rather than the first.

That successor is now wanted, and it moves a constraint. One sentence fits in a message box; an
unbounded list does not. `MessageDlg` renders a single static label with no scrolling, so a file whose
timestamps are all in the wrong format would produce a dialog taller than the screen — less usable
than the one sentence it replaced, not more.

Forces at play:

- The point of listing every problem is a file the user can fix in one pass. That means each line has
  to keep the record number and the offending value, which is what the existing message already
  carries.
- A person fixing a file wants to copy the text out, or at least read it without the window fighting
  back.
- `src/Repository` may not show anything (ADR 0001). `LoadEventsFromFile` can only hand out values, so
  the choice of presentation belongs entirely to `src/UI`.
- ADR 0012 split the form into plain classes driving controls the form owns, and turned down frames
  because each extra designer file is another place for the IDE to inject noise into the project.

## Options

### Option 1 — keep one dialog, cap the list

Collect the first N problems, print them as lines in the same `MessageDlg`, and end with "…and X more".

- Pro: no new form, no new file; the change is a handful of lines.
- Pro: the dialog can never outgrow the screen.
- Con: the cap is arbitrary, and the records past it are exactly the ones nobody hears about.
- Con: text in a message box cannot be selected or copied.

### Option 2 — group the problems by kind

Reduce them to one line per kind of failure: "3 records have no time; 2 have an unknown severity".

- Pro: bounded by the number of failure kinds, so it can never overflow.
- Pro: describes the shape of a broken file better than a list of near-identical lines.
- Con: loses the record numbers, which is the part that tells the user where to look.
- Con: `TryElementToEvent` would have to return a kind alongside the text, which is a wider change to
  the layer that is currently only formatting a sentence.

### Option 3 — a window of its own

A small modal form: a summary label, a read-only multi-line control holding every problem, one Close
button.

- Pro: no cap, no truncation, and the list scrolls instead of growing.
- Pro: the text is selectable, so problems can be copied into an editor beside the file.
- Pro: the window is resizable, which a message box is not.
- Con: a new unit and a new `.dfm`, which is the cost ADR 0012 declined to pay for the main form's
  blocks.
- Con: two presentation paths for one report — a message box on the clean path, a window on the dirty
  one.

## Decision

**Every rejected record is reported, and when there is at least one, the report opens in its own modal
window rather than a message box.** The clean import keeps its message box.

Option 3 won on the thing the change was asked for. Capping is the failure the feature exists to fix:
a list that stops at five is a longer version of the sentence it replaced, and the file the user most
needs help with — the one broken all the way through — is the one the cap hides. Grouping loses the
record numbers, and without them "3 records have no time" sends the reader back to scanning the file
by hand.

The cost ADR 0012 was avoiding does not really apply here. It declined *frames* for blocks used once
inside a window the designer already owned, where the layout would have been scattered across four
files for no reuse. This is a separate window with its own lifetime, created on demand and freed on
close; it has nowhere else to live, and a `.dfm` is the ordinary way to describe it.

`TImportReport` therefore carries `Problems: TArray<string>` instead of a single `FirstProblem`, and
`Rejected` stops being a stored field: with nothing capped it is exactly `Length(Problems)`, and two
fields holding the same number is one more thing that can disagree. `Accepted` was already derived the
same way, from `Length` of the events returned.

The two presentation paths are accepted, because they are not two versions of one thing. A clean
import is an acknowledgement — one line, dismissed without reading. A dirty one is a work list.

## Consequences

Easier: fixing a file, which now takes one import instead of one import per broken record; showing
that the application withstands bad input, since `sample-events-invalid.json` produces seven named
problems in one window.

Harder: `src/UI` gains a designer file, and with it the `.dproj` noise ADR 0012 warned about — the
`<FormType>dfm</FormType>` element the IDE likes to drop has to be watched in `git diff` for a second
unit now.

The list is unbounded on purpose, and that is the thing to watch. A file with a hundred thousand broken
records will build a hundred thousand strings and put them all in one control. Nothing in the
assignment produces a file like that, and the memory is transient, but a real import path would want
either a cap with an honest "…and X more" or a problems view that streams. Should that day come, the
control changes and `TImportReport` does not: it already hands out the whole list, and the decision
about how much of it to draw belongs to the window.
