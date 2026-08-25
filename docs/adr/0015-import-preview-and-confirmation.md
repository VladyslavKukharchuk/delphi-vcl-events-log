# 0015. Import is previewed and confirmed before anything is stored

- **Status:** accepted
- **Date:** 2026-08-24
- **Supersedes:** [ADR 0014](0014-import-problems-window.md), whose window reported rejected records
  after the import had already happened
- **Revises:** the commit half of [ADR 0009](0009-json-import-semantics.md), which stored what the file
  yielded without asking

## Context

ADR 0014 gave rejected records a window of their own, and it works — but it opens *after* the events
are in the database. The user learns what the file cost them at the moment when nothing can be done
about it.

That is the smaller half. The larger half was written down in ADR 0009 and accepted knowingly: import
appends and identifiers are minted, so importing the same file twice stores its events twice, and the
only remedy named there is deleting the database file. A mis-clicked import is permanent, and the
report that would have warned the user arrives one step too late to matter.

- Parsing and storing are already separate. `LoadEventsFromFile` returns an array and touches nothing;
  `TEventActions.Import` is the only caller of `InsertMany`. A decision point between the two costs no
  change to the model, the repository or the importer.
- Showing what a file will contribute before it contributes it is the robustness requirement read one
  step earlier — but it is an interpretation, and the statement does not ask for a confirmation step
  in so many words.
- The events that survived are as interesting as the ones that did not: a file can parse perfectly
  and still be the wrong file.

## Options

### Option 1 — keep reporting after the fact

- Pro: already written; the happy path is one click.
- Con: the information arrives after the only moment it could have been used.
- Con: leaves import permanent and unreviewable, which is the sharpest edge in the application.

### Option 2 — preview, then confirm

Parse into memory, show what was read and what was rejected, store only on confirmation.

- Pro: the decision is made where the information is, and cancelling costs nothing.
- Pro: reuses the window from ADR 0014 rather than replacing it — the problems list becomes one tab.
- Con: one extra click on a clean file.
- Con: the whole file is held in memory before anything is committed. It already was.

### Option 3 — import, then offer undo

- Pro: no click on the happy path.
- Con: needs a batch identifier in the schema (ADR 0006) and a delete-by-batch in the repository.
- Con: undo is a feature with its own questions — how long it stays available, what happens after the
  generator has appended more rows — and nothing has asked for it.

## Decision

**Import parses the file, shows a modal preview of what it found, and stores nothing unless the user
confirms.** The preview always opens, including for a file with no problems at all.

Option 2 won because the cost is a click and the thing it buys is the reversibility the application
otherwise lacks. Option 3 buys the same reversibility for a schema change and a new feature.

The preview always opening is the part worth defending. A dialog that appears only when something
went wrong trains the user to read it as an error, and a clean file then commits itself with no
moment of review — so the one case where the user picked the wrong file is exactly the case with no
way to stop.

`TImportPreviewForm` carries a summary line and two tabs: the events that would be imported, in the
same columns as the main table, and the problems, in the read-only memo ADR 0014 already justified.
The events tab is `OwnerData` like the main table (ADR 0008), so a large file does not build a
`TListItem` per row for a list that may be thrown away a second later. `Import` is disabled when
nothing survived. The contract stays a value in, a decision out:

```pascal
function ConfirmImport(const AFileName: string; const AReport: TImportReport;
  const AEvents: TArray<TLogEvent>): Boolean;
```

The window knows nothing about the repository, and `TEventActions` knows nothing about the controls.

**The message shown after a successful import is removed.** It existed to tell the user what had
happened; now the user decided what would happen, one dialog earlier, looking at the same numbers.

## Consequences

Identity moves, quietly. ADR 0009 said identity belongs to the act of importing; with a preview it
belongs to the act of *parsing*, because `TLogEvent.New` mints the GUIDs while the file is read and
the import may then never happen. Two previews of the same file therefore show different identifiers
for the same records — which is why the events tab shows time, severity and text, and not the id.

The generator keeps recording while the preview is open. The modal blocks the import, not the
application: queued events continue to reach the database behind the dialog. That is correct — those
events are not part of the decision being made — but it means the view can differ before and after
the preview for reasons that have nothing to do with the file.
