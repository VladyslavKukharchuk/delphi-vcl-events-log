# 0015. Import is previewed and confirmed, and every rejected record is listed

- **Status:** accepted
- **Date:** 2026-08-24
- **Revises:** the reporting and commit halves of [ADR 0009](0009-json-import-semantics.md), which kept
  only the first problem and stored what the file yielded without asking

## Context

ADR 0009 settled that a record which cannot be read is skipped rather than failing the whole import,
and that something is said about it afterwards. What it said was deliberately thin: a count and the
text of the *first* problem, in the same `MessageDlg` as the success line. Two things are wrong with
that, and the larger one is not the one it looks like.

**Only the first problem is named.** A file broken in five ways takes five imports to fix. Naming
every problem is the obvious successor, and it moves a constraint: one sentence fits in a message
box, an unbounded list does not. `MessageDlg` renders a single static label with no scrolling, so a
file whose timestamps are all in the wrong format would produce a dialog taller than the screen.

**The report arrives too late to be worth reading.** ADR 0009 accepted knowingly that import appends
and identifiers are minted, so importing the same file twice stores its events twice and the only
remedy is deleting the database file. A mis-clicked import is permanent, and a report of what the
file cost the user opens at the moment when nothing can be done about it.

Parsing and storing are already separate — `LoadEventsFromFile` returns an array and touches nothing,
and `TEventActions.Import` is the only caller of `InsertMany` — so a decision point between the two
costs no change to the model, the repository or the importer. Whatever is shown, `src/Repository` may
not show it (ADR 0001).

## Options

### How the rejected records are reported

1. **Keep one dialog, cap the list.** Print the first N problems and end with "…and X more". Pro: no
   new form, and the dialog can never outgrow the screen. Con: the cap is arbitrary, and the file
   broken all the way through is the one it hides. Con: message-box text cannot be copied.
2. **Group by kind.** "3 records have no time; 2 have an unknown severity". Pro: bounded by the number
   of failure kinds. Con: loses the record numbers, which is the part that says where to look.
3. **A window of its own.** A summary label, a read-only multi-line control holding every problem, one
   button. Pro: no cap and no truncation; the list scrolls, the text is selectable, the window is
   resizable. Con: a new unit and a new `.dfm`, the cost ADR 0012 declined for the form's blocks.

### When the user decides

1. **After the fact.** Store, then show what was skipped. Pro: the happy path is one click. Con: the
   information arrives after the only moment it could have been used, and import stays permanent and
   unreviewable — the sharpest edge in the application.
2. **Preview, then confirm.** Parse into memory, show what was read and what was rejected, store only
   on confirmation. Pro: the decision is made where the information is, and cancelling costs nothing.
   Con: one extra click on a clean file, and the whole file is held in memory before anything is
   committed — it already was.
3. **Import, then offer undo.** Pro: no click on the happy path. Con: needs a batch identifier in the
   schema (ADR 0006) and a delete-by-batch in the repository. Con: undo is a feature with its own
   questions — how long it stays available, what happens after the generator has appended more rows —
   and nothing has asked for it.

## Decision

**Import parses the file, shows a modal preview of what it found — every rejected record named, in
full — and stores nothing unless the user confirms.** The preview always opens, including for a file
with no problems at all.

The window won over a capped dialog because capping is the failure the feature exists to fix: a list
that stops at five is a longer version of the sentence it replaced. Grouping loses the record
numbers, and without them "3 records have no time" sends the reader back to scanning the file by
hand. The `.dfm` cost ADR 0012 was avoiding does not apply — it declined *frames* for blocks used
once inside a window the designer already owned; this is a separate window with its own lifetime.

The preview won over reporting after the fact because the cost is a click and the thing it buys is
the reversibility the application otherwise lacks. Undo buys the same reversibility for a schema
change and a new feature.

The preview always opening is the part worth defending. A dialog that appears only when something
went wrong trains the user to read it as an error, and a clean file then commits itself with no
moment of review — so the one case where the user picked the wrong file is exactly the case with no
way to stop.

`TImportPreviewForm` carries a summary line and two tabs: the events that would be imported, in the
same columns as the main table, and the problems, in a read-only memo. The events tab is `OwnerData`
like the main table (ADR 0008), so a large file does not build a `TListItem` per row for a list that
may be thrown away a second later. `Import` is disabled when nothing survived. The contract stays a
value in, a decision out:

```pascal
function ConfirmImport(const AFileName: string; const AReport: TImportReport;
  const AEvents: TArray<TLogEvent>): Boolean;
```

The window knows nothing about the repository, and `TEventActions` knows nothing about the controls.
`TImportReport` carries `Problems: TArray<string>` rather than a single `FirstProblem`, and `Rejected`
stops being a stored field: with nothing capped it is exactly `Length(Problems)`, and two fields
holding the same number is one more thing that can disagree. The message shown *after* a successful
import is removed with all this — the user now decides what will happen, one dialog earlier, looking
at the same numbers.

## Consequences

Identity moves, quietly. ADR 0009 said identity belongs to the act of importing; with a preview it
belongs to the act of *parsing*, because `TLogEvent.New` mints the GUIDs while the file is read and
the import may then never happen. Two previews of the same file therefore show different identifiers
for the same records — which is why the events tab shows time, severity and text, and not the id.

The generator keeps recording while the preview is open. The modal blocks the import, not the
application: queued events continue to reach the database behind the dialog. That is correct — those
events are not part of the decision being made — but it means the view can differ before and after
the preview for reasons that have nothing to do with the file.

The problems list is unbounded on purpose. A file with a hundred thousand broken records builds that
many strings and puts them all in one control; the memory is transient, but a real import path would
want a cap with an honest "…and X more". The control would change and `TImportReport` would not.
