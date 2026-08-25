# Architecture decision records

Every decision that is hard to reverse, or that a reviewer could reasonably question, is recorded
here. Each record states the problem, the alternatives considered, and why one of them won.

Records are append-only: when a decision changes, a new record supersedes the old one and both stay.
The Status column below says which are still current, so nothing has to be read to find that out.

| # | Decision | Status |
|---|---|---|
| [0001](0001-layer-folders-under-src.md) | Layer folders under `src/`, plain classes, one-way `uses` | current; composition superseded by 0013 |
| [0002](0002-log-event-as-a-value-type.md) | `TLogEvent` is a `record`, so a snapshot cannot be invalidated | current |
| [0003](0003-uuid-event-identifiers.md) | Identifiers are `TGUID`, minted by whoever creates the event | current |
| [0004](0004-sqlite-for-local-persistence.md) | SQLite through FireDAC, statically linked into the `.exe` | current |
| [0005](0005-database-file-location.md) | The database lives in `%LOCALAPPDATA%\EventsLog\events.db` | current |
| [0006](0006-database-schema-and-encodings.md) | One `events` table; ISO 8601 time, canonical UUID text | current |
| [0007](0007-event-repository.md) | One `insert` per event, one connection on the UI thread, re-query to refresh | current; import revised by 0009 |
| [0008](0008-listview-for-the-events-table.md) | A virtual `TListView` in report mode | current; status line removed by 0017 |
| [0009](0009-json-import-semantics.md) | Import appends, identifiers are minted, bad records are skipped and reported | current; reporting revised by 0014, commit by 0015 |
| [0010](0010-search-and-severity-filter.md) | Substring search on every keystroke; severity as one drop-down | current; match count and query limit removed by 0017 |
| [0011](0011-event-generator-thread.md) | A `TThread` that exists only while it runs, waiting on a `TEvent` | current |
| [0012](0012-splitting-the-form-into-ui-blocks.md) | The form splits into plain blocks driving controls it still owns | current |
| [0013](0013-repository-interface-and-composition-root.md) | `IEventRepository`, with the object graph built in the `.dpr` | current |
| [0014](0014-import-problems-window.md) | Rejected records listed in full, in their own window | **superseded by 0015** |
| [0015](0015-import-preview-and-confirmation.md) | Import is previewed and confirmed before anything is stored | current |
| [0016](0016-schema-setup-separate-from-the-connection.md) | `EnsureSchema` in its own unit, run once by the composition root | current |
| [0017](0017-no-row-counts-and-no-query-limit.md) | Row counts, the query limit and the status bar removed | partly superseded by 0018 |
| [0018](0018-paged-events-table.md) | The table is paged: `Count` plus `Page`, with navigation controls | current |

[0000-template.md](0000-template.md) is the starting point for a new record.
