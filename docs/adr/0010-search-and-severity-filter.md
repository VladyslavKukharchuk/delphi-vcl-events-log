# 0010. Search is a case-folded substring, severity is one level at a time

- **Status:** accepted; the match count and the query limit are superseded by
  [0017](0017-no-row-counts-and-no-query-limit.md)
- **Date:** 2026-08-21

## Context

The statement asks for two things that look like one: searching events by their text, and filtering
them by severity level. They share a window, they share a query, and neither says how it behaves.

Everything needed to answer them already exists. `TEventFilter` carries a search string and a set of
severities, and [ADR 0007](0007-event-repository.md) put the predicate in exactly one place — a SQL
where clause built by the repository, so the criteria travel as data and the rule lives in the
database. What was missing was the half that decides what to put in that record, which is the window.

Forces at play:

- The query is capped at `DefaultQueryLimit` rows and ordered by time descending, so the table already
  shows a window onto the log rather than all of it (D8). A filter narrows what the window looks at,
  not what it holds.
- The search string comes from a person typing. `%` and `_` are ordinary characters to them and
  wildcards to SQL LIKE, and the repository already escapes both.
- SQLite is linked statically without ICU ([ADR 0004](0004-sqlite-for-local-persistence.md)). Its
  `LIKE` folds case for ASCII letters and for nothing else.
- The severity levels are a closed set of three, named once in `SeverityNames`.
- Filtering must not be able to hide the difference between "nothing matches" and "nothing is stored".
  Both show an empty table.

## Options

### What "search by text" means

1. **Substring, case-insensitive.** Pro: what a search box does everywhere else, so nothing has to be
   explained. Con: no way to ask for whole words or for a prefix.
2. **Prefix match.** Pro: an index could serve it. Con: nobody remembers how an event message starts;
   the interesting words are in the middle of it.
3. **Whole words, or a small query language.** Pro: precise. Con: a syntax to document and to get
   wrong, for a table of a few thousand rows that a substring scan searches instantly.

### When the filter is applied

1. **On every keystroke.** Pro: the table answers while the user is still deciding what to look for,
   and a wrong letter is visibly wrong at once. Con: one query per character.
2. **On Enter, or behind a Search button.** Pro: one query per search. Con: a button that must be
   pressed for the window to stop lying about what it is showing, and an extra control for a query
   that costs a millisecond.
3. **On a keystroke, debounced by a timer.** Pro: the responsiveness of the first with the query count
   of the second. Con: a timer, a state to reset and a delay to justify, for a cost that has not been
   measured and, at this scale, cannot be felt.

### How severity is chosen

1. **Three checkboxes, one per level.** Pro: matches `TSeveritySet` exactly, so any combination is
   expressible — Warning and Error together is the combination someone actually wants. Con: three
   controls and eight states, one of which (nothing checked) means an empty table for no obvious
   reason.
2. **One drop-down: All, Info, Warning, Error.** Pro: one control, four states, no state that shows
   nothing by accident. Pro: reads as a question with an answer rather than as a form to fill in. Con:
   the set type can express more than the control can ask for, so "Warning and Error" is out of reach.

### What the window says while filtered

1. **Nothing — the table speaks for itself.** Con: an empty table under a filter is
   indistinguishable from an empty database, and a capped result is indistinguishable from a complete
   one.
2. **The count of matches beside the count stored.** Pro: zero matches out of two hundred stored is a
   sentence that cannot be misread. Con: needs a second count query, so the repository grows a
   `Count(AFilter)` overload beside the plain one.

## Decision

**Search is a case-folded substring, applied on every keystroke. Severity is a drop-down that selects
one level or all of them. The status bar states matches against what is stored.**

The substring won because it is the only behaviour that needs no explanation, and because the two
alternatives buy precision that this data cannot use: log messages are sentences, and the words worth
searching sit in the middle of them.

Filtering on each keystroke won on honesty rather than on convenience. Any deferred variant leaves the
window in a state where the text box says one thing and the table shows another, and the user has to
know that a keypress is what reconciles them. The query it costs is a `LIKE` over a bounded table on a
local file, run between two keystrokes by a person; the debounced middle ground optimises that at the
price of a timer and a delay, which is machinery bought before the problem exists. If the log ever
grows enough for typing to stutter, the timer is a small, local change and this paragraph is the note
that says so.

The drop-down won over the checkboxes on the state it makes impossible. Checkboxes match the type —
`TSeveritySet` is a set, and Warning-and-Error is a real request — but they also let a user clear all
three and face an empty table that no message can explain better than "you asked for no severities".
Four mutually exclusive answers cannot be put into that state. The set type keeps its shape and stays
the interface between the form and the repository, so widening the control to checkboxes later changes
one function, `SelectedSeverities`, and nothing behind it.

**The case folding is ASCII only, and this is accepted rather than fixed** (D12). Searching for
`error` finds `Error`, because SQLite's `LIKE` folds the letters A to Z. Searching for `помилка` will
not find `Помилка`, because it folds nothing else. The two ways out both cost more than the limit
does here: a lowercased shadow column filled by Delphi's Unicode-aware `ToLower` means a schema
change, a migration for databases that already exist, an extra column written on every insert and a
second copy of every message on disk; a Unicode-aware `lower()` registered as a user-defined function
means SQL that depends on the application having installed it, which the file no longer means the same
thing without. The sample data and the generated events are English, so the limit is not visible in
what this application does — but it is a limit, not a property, and it belongs in the README under
what could be improved rather than in a comment nobody reads.

## Consequences

Easier: narrowing a log to the errors of the last hour, which is the reason someone opens a log
viewer at all. The predicate stayed in one place, so search and filter compose without either half
knowing about the other, and the count query reuses the same `WhereClause` — the criteria cannot mean
one thing to the table and another to the number under it.

Harder: every refresh now runs two statements instead of one where a filter is active, and a filtered
view refreshes on each generated event once the generator exists. Both are counts over a bounded
table, and the unfiltered case still runs one, because a filter that hides nothing has nothing to
count separately.

To revisit if the assumptions change: a log large enough that counting hurts, which would mean
dropping the exact match count for a cheaper "more than the limit" test; a request to search
non-English text case-insensitively, which is the shadow column and a migration; or a request for two
severity levels at once, which is the checkboxes and one rewritten function.
