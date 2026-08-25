# 0010. Search is a case-folded substring, severity is one level at a time

- **Status:** accepted; the match count and the query limit behind it are superseded by
  [0018](0018-paged-events-table.md)
- **Date:** 2026-08-21

## Context

The statement asks for two things that look like one: searching events by text and filtering them by
severity. They share a window and a query, and neither says how it behaves.

Everything below them already exists. `TEventFilter` carries a search string and a set of severities,
and [ADR 0007](0007-event-repository.md) put the predicate in exactly one place — a SQL `where`
clause built by the repository. What was missing is the half that decides what to put in that record.

- The search string comes from a person typing. `%` and `_` are ordinary characters to them and
  wildcards to SQL LIKE; the repository escapes both.
- SQLite is linked statically without ICU (ADR 0004). Its `LIKE` folds case for ASCII letters and for
  nothing else.
- The severity levels are a closed set of three, named once in `SeverityNames`.
- Filtering must not hide the difference between "nothing matches" and "nothing is stored". Both show
  an empty table.

## Options

### What "search by text" means

1. **Substring, case-insensitive.** Pro: what a search box does everywhere else, so nothing has to be
   explained. Con: no way to ask for whole words or a prefix.
2. **Prefix match.** Pro: an index could serve it. Con: nobody remembers how a message starts; the
   interesting words are in the middle.
3. **Whole words, or a small query language.** Pro: precise. Con: a syntax to document and to get
   wrong, for a table a substring scan searches instantly.

### When the filter is applied

1. **On every keystroke.** Pro: the table answers while the user is still deciding, and a wrong
   letter is visibly wrong at once. Con: one query per character.
2. **On Enter, or behind a Search button.** Con: a button that must be pressed for the window to stop
   lying about what it is showing.
3. **Debounced by a timer.** Pro: the responsiveness of the first with the query count of the second.
   Con: a timer, a state to reset and a delay to justify, for a cost that has not been measured.

### How severity is chosen

1. **Three checkboxes, one per level.** Pro: matches `TSeveritySet` exactly, so Warning-and-Error is
   expressible. Con: eight states, one of which — nothing checked — means an empty table for no
   obvious reason.
2. **One drop-down: All, Info, Warning, Error.** Pro: four states and no state that shows nothing by
   accident; it reads as a question with an answer rather than a form to fill in. Con: the set type
   can express more than the control can ask for.

### What the window says while filtered

1. **Nothing.** Con: an empty table under a filter is indistinguishable from an empty database.
2. **The count of matches beside the count stored.** Pro: zero matches out of two hundred stored is a
   sentence that cannot be misread. Con: a second count query, so the repository grows a
   `Count(AFilter)` overload.

## Decision

**Search is a case-folded substring, applied on every keystroke. Severity is a drop-down that selects
one level or all of them. The status bar states matches against what is stored.**

The substring won because it needs no explanation, and the alternatives buy precision this data
cannot use: log messages are sentences, and the words worth searching sit in the middle of them.

Filtering on each keystroke won on honesty rather than convenience. Any deferred variant leaves the
window in a state where the text box says one thing and the table shows another. The query it costs
is a `LIKE` over a bounded local table, run between two keystrokes by a person; the debounced middle
ground optimises that at the price of a timer and a delay, which is machinery bought before the
problem exists. If the log ever grows enough for typing to stutter, the timer is a small local change
and this paragraph is the note that says so.

The drop-down won over checkboxes on the state it makes impossible. Checkboxes match the type, but
they also let a user clear all three and face an empty table that no message can explain better than
"you asked for no severities". The set type keeps its shape and stays the interface between the form
and the repository, so widening the control later changes one function, `SelectedSeverities`, and
nothing behind it.

**The case folding is ASCII only, and this is accepted rather than fixed.** Searching for `error`
finds `Error`; searching for `помилка` will not find `Помилка`. Both ways out cost more than the
limit does here — a lowercased shadow column means a schema change, a migration and a second copy of
every message on disk, and a Unicode-aware `lower()` registered as a user-defined function means SQL
that depends on the application having installed it. The sample data and the generated events are
English, so the limit is not visible in what this application does; it belongs in the README under
what could be improved.

## Consequences

Every refresh runs two statements instead of one where a filter is active, and the count query reuses
the same `WhereClause` — so the criteria cannot mean one thing to the table and another to the number
under it.
