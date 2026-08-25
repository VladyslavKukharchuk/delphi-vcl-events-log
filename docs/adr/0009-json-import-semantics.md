# 0009. Import appends, identifiers are minted, and how wrong a file may be

- **Status:** accepted; the reporting half is revised by [0014](0014-import-problems-window.md), the
  commit half by [0015](0015-import-preview-and-confirmation.md)
- **Date:** 2026-08-21
- **Revises:** the import half of [ADR 0007](0007-event-repository.md), which had import replacing the
  stored history

## Context

The statement asks for event history to be loaded from a JSON file, and separately for the
application to withstand a malformed file or invalid data. Three questions follow.

**What does importing do to what is already stored?** ADR 0007 assumed it replaced it. That
assumption does not survive persistence: the generator adds an event a second and every import adds
more, so a store wiped by each import is not a log but a view of the last file opened.

**Does the file carry identity?** If the file supplies an `id`, the application inherits whatever the
file got wrong. If the application mints one, two imports of the same file are indistinguishable from
two imports of different files.

**What counts as too wrong to import?** Two kinds of wrong exist and they are not the same. A file
that is not JSON, or is JSON but not an array, carries nothing usable. A file of two hundred events
in which three records lack a timestamp carries a hundred and ninety-seven usable events.

`src/Repository` may not show a dialog (ADR 0001), so whatever it learns travels out as a value or an
exception.

## Options

### What import does to the stored history

1. **Replace.** Pro: the table shows exactly what the last file said. Con: destroys events the
   generator produced and everything from earlier imports — data loss as a feature.
2. **Append.** Pro: the store becomes what it claims to be, a log that grows, and two files can be
   loaded one after the other. Con: nothing removes events any more, so the only route back to empty
   is deleting the database file.

### Where the identifier comes from

1. **From the file, minted only when absent.** Pro: stable identity, so re-importing is recognisable
   and could be a no-op. Con: an unreadable `id` becomes a category of broken record, and a
   hand-written sample file has to contain UUIDs to be useful.
2. **Always minted by the application.** Pro: the file is pure content — three keys per record. Pro:
   one rule with no branches, and no way for a bad `id` to reject an otherwise good record. Con:
   identity becomes a property of *the act of importing*, so the same file imported twice is stored
   twice.

### How much a record may be wrong

1. **Strict: any bad record fails the whole import.** Pro: no partial state to explain. Con: one typo
   in a two-hundred-event file imports nothing.
2. **Tolerant and silent: skip what cannot be read.** Con: silence is the failure mode — ten skipped
   records look identical to a file that only had the rest.
3. **Tolerant and reported: skip, count, and say what went wrong.** Pro: nothing usable is lost and
   nothing broken is hidden. Con: the loader returns two things.

Parsing goes through `ParseJSONValue` into a DOM rather than the streaming `TJsonTextReader`: the
whole document is in hand, so per-record recovery is a loop with an index, and it returns nil for
invalid JSON rather than raising. The cost is the file in memory twice.

## Decision

**Import appends. Identifiers are always minted by the application. Records that cannot be read are
skipped and reported.**

Append won because the store is now a log: events arrive from the generator over time and from each
import, and both are additions to one history. Replacement would mean opening a file discards
whatever the generator recorded overnight.

Minting every identifier won on the shape of the file. `time`, `text` and `severity` are what an
event *is*; an `id` is bookkeeping, and requiring a UUID in every record would make the sample file —
itself a deliverable someone reads — noise around the three fields that matter. It also removes a
whole category of failure. An `id` key in a file is simply ignored, like any other unknown key.

The cost is accepted with open eyes: **identity now belongs to the act of importing, not to the
event.** The same file imported twice is stored twice. `insert or ignore` would be theatre — with
minted keys there is nothing to collide — so the insert is plain and the duplication is honest rather
than hidden.

Two failure modes, two mechanisms:

- **The file is unusable** — unreadable, not valid JSON, or its root is not an array. There is nothing
  to return, so `EEventImportError` is raised naming the file and the stored history is untouched.
- **A record is unusable** — not an object, or missing or unreadable `time`, `text` or `severity`. It
  is skipped and its problem kept, so the report can name every record the file lost.

What counts as unusable is deliberately narrow. `severity` is matched case-insensitively against the
same `SeverityNames` the rest of the application uses, so `ERROR` and `error` both pass while
`Critical` does not: an unknown level rejects the record rather than silently becoming `Info`,
because guessing at severity is worse than admitting the record is broken.

`time` is read by the RTL's `TryISO8601ToDate` with `ioNoTZIsLocal` — no offset means local time,
while a `Z` or an explicit `+03:00` is honoured and converted; a hand-rolled reader had silently
dropped the `Z` and rejected the offset form outright. Writing still goes through `FormatDateTime`,
because `DateToISO8601` always appends a `Z` and would declare a local time to be UTC. An absent key
and a key holding the wrong kind of value are also distinguished, because `TryGetValue<string>`
conflates them and `"severity": 3` would otherwise be reported as a record that *has no severity*.

Three sample files ship rather than one, because a claim about withstanding bad input is worth being
able to demonstrate: `sample-events.json`, `sample-events-invalid.json` (valid JSON, records broken in
seven ways) and `sample-events-malformed.json` (not JSON at all).

## Consequences

Re-importing is not idempotent, and no warning can be given at the time, because the application
cannot tell it has seen these events before. Append also made one absence conspicuous: with nothing
removing events, the only route back to empty would have been deleting the database file. So the
window carries a Clear button behind a confirmation defaulting to No. It is deliberately
all-or-nothing — per-event deletion is a different feature with its own questions about selection and
undo. Clearing is the one irreversible action in the application, and it sits next to Import on the
same toolbar.
