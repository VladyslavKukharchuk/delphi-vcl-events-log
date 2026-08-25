# 0014. Rejected records get their own window, listed in full

- **Status:** superseded by [0015](0015-import-preview-and-confirmation.md)
- **Date:** 2026-08-24
- **Revises:** the reporting half of [ADR 0009](0009-json-import-semantics.md), which kept only the
  first problem

## Context

ADR 0009 settled that a record which cannot be read is skipped rather than failing the whole import,
and that something is said about it afterwards. What it said was deliberately thin — a count and the
text of the *first* problem, shown in the same `MessageDlg` as the success line. Its own "to revisit"
list named the successor: report every problem rather than the first.

That moves a constraint. One sentence fits in a message box; an unbounded list does not. `MessageDlg`
renders a single static label with no scrolling, so a file whose timestamps are all in the wrong
format would produce a dialog taller than the screen — less usable than the one sentence it replaced.

The point of listing every problem is a file the user can fix in one pass, so each line has to keep
the record number and the offending value, and the text has to be readable and ideally copyable.
`src/Repository` may not show anything (ADR 0001), so the choice of presentation belongs to `src/UI`.

## Options

### Option 1 — keep one dialog, cap the list

Print the first N problems in the same `MessageDlg` and end with "…and X more".

- Pro: no new form, no new file; the dialog can never outgrow the screen.
- Con: the cap is arbitrary, and the records past it are exactly the ones nobody hears about.
- Con: text in a message box cannot be selected or copied.

### Option 2 — group the problems by kind

"3 records have no time; 2 have an unknown severity".

- Pro: bounded by the number of failure kinds, and describes the shape of a broken file well.
- Con: loses the record numbers, which is the part that tells the user where to look.
- Con: `TryElementToEvent` would have to return a kind alongside the text.

### Option 3 — a window of its own

A small modal form: a summary label, a read-only multi-line control holding every problem, one Close
button.

- Pro: no cap and no truncation; the list scrolls instead of growing, the text is selectable, and the
  window is resizable.
- Con: a new unit and a new `.dfm`, which is the cost ADR 0012 declined for the main form's blocks.
- Con: two presentation paths for one report.

## Decision

**Every rejected record is reported, and when there is at least one, the report opens in its own
modal window rather than a message box.** The clean import keeps its message box.

Capping is the failure the feature exists to fix: a list that stops at five is a longer version of
the sentence it replaced, and the file the user most needs help with — the one broken all the way
through — is the one the cap hides. Grouping loses the record numbers, and without them "3 records
have no time" sends the reader back to scanning the file by hand.

The cost ADR 0012 was avoiding does not apply here. It declined *frames* for blocks used once inside
a window the designer already owned; this is a separate window with its own lifetime, created on
demand and freed on close. It has nowhere else to live, and a `.dfm` is the ordinary way to describe
it.

`TImportReport` therefore carries `Problems: TArray<string>` instead of a single `FirstProblem`, and
`Rejected` stops being a stored field: with nothing capped it is exactly `Length(Problems)`, and two
fields holding the same number is one more thing that can disagree.

The two presentation paths are accepted, because they are not two versions of one thing. A clean
import is an acknowledgement, dismissed without reading. A dirty one is a work list.

## Consequences

The list is unbounded on purpose. A file with a hundred thousand broken records will build a hundred
thousand strings and put them all in one control — nothing in the assignment produces such a file and
the memory is transient, but a real import path would want either a cap with an honest "…and X more"
or a problems view that streams. The control would change and `TImportReport` would not.
