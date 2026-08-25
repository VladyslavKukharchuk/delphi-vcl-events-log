# 0008. A virtual TListView for the events table

- **Status:** accepted; the status line is superseded by [0018](0018-paged-events-table.md)
- **Date:** 2026-08-21

## Context

The statement requires a main window showing the events in a table with every attribute visible. What
that table is built from has to be decided once, because the control's model decides how the rest of
the UI is written.

- The row count changes constantly: the generator appends every second, and every filter change
  replaces the whole result set.
- What the table shows is a `TArray<TLogEvent>` produced by a query — already ordered, filtered and
  capped. The control does not need to sort, filter or store anything.
- ADR 0001 keeps controls inside `src/UI` and ADR 0004 forbids a `TDataSet` from leaving
  `src/Repository`, so a `TDBGrid` bound to a `TDataSource` is out by construction: it would put the
  query in the form and make the layering decorative.
- The identifier is a full UUID, 36 characters, and every attribute has to be displayed.

## Options

### Option 1 — `TListView` in `vsReport` with `OwnerData = True`

Virtual mode: the control holds no items and asks for a row when it needs to paint it.

- Pro: the array stays the single copy of the data. Replacing it and setting `Items.Count` is the
  whole refresh.
- Pro: repainting costs the visible rows, so a thousand rows behave like ten.
- Pro: native report columns, header and row selection — the look users expect, free.
- Con: `OnData` runs during painting, so it must be cheap and must never raise.

### Option 2 — `TListView` with real items

- Pro: no virtual-mode rules to respect.
- Con: every refresh builds and frees a thousand `TListItem` objects, once a second.
- Con: the data exists twice — in the array and in the control — and the two can disagree.

### Option 3 — `TStringGrid` or `TDrawGrid`

- Pro: full control over cells and drawing.
- Con: `TStringGrid` stores its contents as strings, so the data exists twice and everything becomes
  text early; `TDrawGrid` paints every cell by hand. Freedom a four-column log window does not need.

## Decision

Option 1 — `TListView`, `ViewStyle = vsReport`, `OwnerData = True`, with `OnData` reading the array
the last query produced.

The control's model matches what the application already has. The array is ordered, filtered and
capped before it arrives, so a control that manages its own items would duplicate a job already done
— and duplicate the data with it. Virtual mode makes the array the single source of truth, and a
refresh becomes two statements: assign the array, set the count. Option 2 loses on churn that happens
once a second for no benefit; Option 3 buys drawing freedom paid for in code.

**The identifier is shown in full.** A truncated UUID would be shorter but also a value the user
cannot copy, compare or paste into a query, and the statement asks for attributes to be displayed
rather than hinted at. The cost is a 250-pixel column and a window 1000 pixels wide.

**The window states when the view is capped.** The query is limited, so the table can show fewer rows
than the database holds. A status line reading "showing the 1000 most recent of 4318 events" is not a
convenience — without it the window silently implies that what is visible is everything.

## Consequences

`Items.Count` and `Length(FVisible)` have to move together. They are assigned on adjacent lines in
`RefreshView` for exactly that reason, and any future path that replaces the array elsewhere would be
a way to make the control ask for a row that no longer exists.
