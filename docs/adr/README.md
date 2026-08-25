# Architecture decision records

Fifteen records, each stating a problem, the alternatives that were in play, and why one of them won.
They are grouped below by what they decide rather than by number, because that is the order they are
worth reading in; the numbers stay chronological.

## The shape of the code

| # | Decision |
|---|---|
| [0001](0001-layer-folders-under-src.md) | Layer folders under `src/`, plain classes, one-way `uses` — no ports, no presenter |
| [0012](0012-splitting-the-form-into-ui-blocks.md) | The form splits into blocks that drive controls it still owns |
| [0013](0013-repository-interface-and-composition-root.md) | `IEventRepository`, with the object graph built in the `.dpr` |

## The event

| # | Decision |
|---|---|
| [0002](0002-log-event-as-a-value-type.md) | `TLogEvent` is a `record`, so a snapshot cannot be invalidated |
| [0003](0003-uuid-event-identifiers.md) | Identifiers are `TGUID`, minted by whoever creates the event |

## Storage

| # | Decision |
|---|---|
| [0004](0004-sqlite-for-local-persistence.md) | SQLite through FireDAC, statically linked into the `.exe` |
| [0005](0005-database-file-location.md) | The database lives in `%LOCALAPPDATA%\EventsLog\events.db` |
| [0006](0006-database-schema-and-encodings.md) | One `events` table; ISO 8601 time, canonical UUID text |
| [0007](0007-event-repository.md) | One `insert` per event, one connection on the UI thread, re-query to refresh |

## The window

| # | Decision |
|---|---|
| [0008](0008-listview-for-the-events-table.md) | A virtual `TListView` in report mode |
| [0010](0010-search-and-severity-filter.md) | Substring search on every keystroke; severity as one drop-down |
| [0018](0018-paged-events-table.md) | The table is paged: `Count` plus `Page`; the status bar is gone |

## Import and generation

| # | Decision |
|---|---|
| [0009](0009-json-import-semantics.md) | Import appends, identifiers are minted, bad records are skipped and reported |
| [0015](0015-import-preview-and-confirmation.md) | Import is previewed and confirmed; every rejected record is listed |
| [0011](0011-event-generator-thread.md) | A `TThread` that exists only while it runs, waiting on a `TEvent` |

## Where a later record changed an earlier one

A decision that changed is revised by a later record rather than rewritten in place, and each of the
four says so in its own header. Nothing below has to be read to follow the ones above.

| Earlier | What changed | Later |
|---|---|---|
| [0001](0001-layer-folders-under-src.md) | the object graph moved out of the form | [0013](0013-repository-interface-and-composition-root.md) |
| [0007](0007-event-repository.md) | import appends instead of replacing | [0009](0009-json-import-semantics.md) |
| [0009](0009-json-import-semantics.md) | every rejected record is reported, and before anything is stored | [0015](0015-import-preview-and-confirmation.md) |
| [0008](0008-listview-for-the-events-table.md), [0010](0010-search-and-severity-filter.md) | the status line and the match count under it | [0018](0018-paged-events-table.md) |

The numbering has gaps: three records were folded into the ones that replaced them rather than kept
as dead ends. [0000-template.md](0000-template.md) is the starting point for a new record.
