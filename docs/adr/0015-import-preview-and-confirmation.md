# 0015. Import is previewed and confirmed before anything is stored

- **Status:** accepted
- **Date:** 2026-08-24
- **Supersedes:** [ADR 0014](0014-import-problems-window.md), whose window reported rejected records
  after the import had already happened
- **Revises:** the commit half of [ADR 0009](0009-json-import-semantics.md), which stored what the file
  yielded without asking, on the grounds that nothing was being destroyed

## Context

ADR 0014 gave rejected records a window of their own, and it works — every problem is named, with the
record number and the offending value. But it opens *after* the events are in the database. The user
learns what the file cost them at the moment when nothing can be done about it.

That is the smaller half of the problem. The larger half was written down in ADR 0009 and accepted
knowingly: import appends and identifiers are minted, so importing the same file twice stores its
events twice, and the application has no way to take them back. The only remedy named there is
deleting the database file. A mis-clicked import is therefore permanent, and the report that would
have warned the user arrives one step too late to matter.

Forces at play:

- Parsing and storing are already separate. `LoadEventsFromFile` returns an array and touches nothing;
  `TEventActions.Import` is the only place that calls `InsertMany`. A decision point between the two
  costs no change to the model, the repository or the importer.
- The statement asks the application to withstand a malformed file or invalid data. Showing what a
  file will contribute before it contributes it is the same requirement read one step earlier, not a
  new feature — but it is an interpretation, and the statement does not ask for a confirmation step in
  so many words.
- The events that survived are as interesting as the ones that did not. A file can parse perfectly and
  still be the wrong file.
- Whatever the window shows, `src/Repository` may not show it (ADR 0001), and the window may not know
  about the repository — otherwise the decision and the act of storing collapse into one place again.

## Options

### Option 1 — keep reporting after the fact

What ADR 0014 built: store, then show what was skipped.

- Pro: already written; the happy path is one click.
- Con: the information arrives after the only moment it could have been used.
- Con: leaves import permanent and unreviewable, which is the sharpest edge in the application.

### Option 2 — preview, then confirm

Parse into memory, show what was read and what was rejected, store only on confirmation.

- Pro: the decision is made where the information is.
- Pro: cancelling costs nothing — nothing was written.
- Pro: reuses the window from ADR 0014 rather than replacing it; the problems list becomes one tab of
  two.
- Con: one extra click on a clean file.
- Con: the whole file is held in memory before anything is committed. It already was.

### Option 3 — import, then offer undo

Store immediately, tag the batch, and let the user roll it back.

- Pro: no click on the happy path.
- Con: needs a batch identifier in the schema (ADR 0006) and a delete-by-batch in the repository.
- Con: undo is a feature with its own questions — how long it stays available, what happens after the
  generator has appended more rows — and nothing has asked for it.

## Decision

**Import parses the file, shows a modal preview of what it found, and stores nothing unless the user
confirms.** The preview always opens, including for a file with no problems at all.

Option 2 won because the cost is a click and the thing it buys is the reversibility the application
otherwise lacks. Option 3 buys the same reversibility for a schema change and a new feature, which is
the wrong trade at this size.

The preview always opening is the part worth defending. A dialog that appears only when something went
wrong trains the user to read it as an error, and a clean file then commits itself with no moment of
review — so the one case where the user picked the wrong file is exactly the case with no way to stop.
One shape for one action is also simpler to explain than two.

The window from ADR 0014 is reused rather than replaced. `TImportPreviewForm` carries a summary line
and two tabs: the events that would be imported, in the same columns as the main table, and the
problems, in the read-only memo that ADR 0014 already justified. The events tab is `OwnerData`, like
the main table (ADR 0008), so a large file does not build a `TListItem` per row for a list that may be
thrown away a second later. `Import` is disabled when nothing survived: there is nothing to confirm,
and only the problems are worth reading.

The contract stays a value in, a decision out:

```pascal
function ConfirmImport(const AFileName: string; const AReport: TImportReport;
  const AEvents: TArray<TLogEvent>): Boolean;
```

The window knows nothing about the repository, and `TEventActions` knows nothing about the controls.
It is a separate unit and a separate form, not a registered VCL component: a palette component earns
its keep by being dropped onto many forms, and this one is used once.

**The message shown after a successful import is removed.** It existed to tell the user what had
happened; now the user decided what would happen, one dialog earlier, looking at the same numbers. The
table and the status bar show the result immediately. `TEventActions.ReportImport` disappears with it.

## Consequences

Easier: recovering from picking the wrong file, which now costs a click on Cancel rather than deleting
the database; judging a file before trusting it, since the events tab shows what would actually land.

Harder: nothing on the code side — the flow the change needed was already the shape of `Import`. On the
user's side, a clean import is now two clicks rather than one.

Identity moves, quietly. ADR 0009 said identity belongs to the act of importing; with a preview it
belongs to the act of *parsing*, because `TLogEvent.New` mints the GUIDs while the file is being read
and the import may then never happen. A cancelled preview throws away identifiers that were never
stored, which harms nothing, but it means two previews of the same file show different identifiers for
the same records. Nothing displays them in the preview, so nobody can notice — and that is the reason
the events tab shows time, severity and text, and not the id.

The generator keeps recording while the preview is open. The modal blocks the import, not the
application: the message loop still runs, so queued events from the generator continue to reach the
database behind the dialog. This is correct — those events are not part of the decision being made —
but it means the counts in the status bar can differ before and after the preview for reasons that have
nothing to do with the file.

To revisit if the assumptions change: files large enough that holding every parsed event in memory
before committing matters, which would push the import towards streaming straight into a transaction
that is rolled back on Cancel; or a request to import only a selection of the previewed events, which
would turn the events tab from a report into a control and would need a decision about what checking a
row means for a log.
