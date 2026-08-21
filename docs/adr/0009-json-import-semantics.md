# 0009. Import appends, identifiers are minted, and how wrong a file may be

- **Status:** accepted
- **Date:** 2026-08-21
- **Revises:** the import half of D9 in [ADR 0007](0007-event-repository.md), which had import
  replacing the stored history

## Context

The statement asks for event history to be loaded from a JSON file, and asks separately for the
application to withstand a malformed file or invalid data. Three questions follow, and each one
constrains the next.

**What does importing do to what is already stored?** ADR 0007 assumed it replaced it, reading "load
the history" as loading a state. That assumption does not survive persistence. Events accumulate now:
the generator adds one a second and every import adds more, so a store wiped by each import is not a
log but a view of the last file opened.

**Does the file carry identity?** An event has an ID, but nothing says the ID has to come from
outside. If the file supplies one, the application inherits whatever the file got wrong. If the
application mints one, the file has no identity at all and two imports of the same file are
indistinguishable from two imports of different files.

**What counts as too wrong to import?** The statement does not say, and the reasonable readings differ
enough to change the code.

Forces at play:

- The file comes from outside. Nothing guarantees its shape, and a reviewer will deliberately feed it
  something broken to see what happens.
- Two kinds of wrong exist and they are not the same. A file that is not JSON, or is JSON but not an
  array, carries nothing usable. A file of two hundred events in which three records lack a timestamp
  carries a hundred and ninety-seven usable events.
- `id` is the primary key (ADR 0006), and ADR 0003 already made identifiers mintable by whoever
  creates the event rather than issued by a counter.
- `src/Repository` may not show a dialog (ADR 0001). Whatever it learns travels out as a value or an
  exception.

## Options

### What import does to the stored history

1. **Replace.** Pro: the table shows exactly what the last file said, which is easy to explain. Con:
   destroys events the generator produced and everything from earlier imports. With persistence in the
   picture, that is data loss as a feature.
2. **Append.** Pro: the store becomes what it claims to be, a log that grows. Pro: two files can be
   loaded one after the other. Con: nothing in the application removes events any more, so the only
   route back to empty is deleting the database file.

### Where the identifier comes from

1. **From the file, minted only when absent.** Pro: a file can carry stable identity, so re-importing
   it is recognisable and can be made a no-op with `insert or ignore`. Con: the file has to be right,
   and an unreadable `id` becomes a category of broken record. Con: a hand-written test file has to
   contain UUIDs to be useful, which is a lot to ask of a sample.
2. **Always minted by the application.** Pro: the file is pure content — a person can write one by
   hand with three keys per record. Pro: one rule with no branches, and no way for a bad `id` to
   reject an otherwise good record. Con: identity stops being a property of the event and becomes a
   property of *the act of importing it*, so importing the same file twice stores its events twice.

### How much a record may be wrong

1. **Strict: any bad record fails the whole import.** Pro: no partial state to explain. Con: one typo
   in a two-hundred-event file imports nothing. For a log this is the wrong trade: a log records what
   happened, and a damaged line does not invalidate the lines around it.
2. **Tolerant and silent: skip what cannot be read.** Pro: everything usable arrives. Con: silence is
   the failure mode. Ten skipped records look identical to a file that only had the rest.
3. **Tolerant and reported: skip, count, and say what went wrong.** Pro: nothing usable is lost and
   nothing broken is hidden. Con: the loader returns two things, so its signature is wider than "read
   this file".

### How to parse

- **`ParseJSONValue` into a DOM.** Pro: the whole document is in hand, so per-record recovery is a loop
  with an index. Pro: it returns nil for invalid JSON rather than raising, so the guarded path is the
  default one. Con: the file is in memory twice, as text and as objects.
- **`TJsonTextReader`, streaming.** Pro: constant memory. Con: recovering from a bad record mid-stream
  means knowing where the record ended, which is real work for no gain at these file sizes.

## Decision

**Import appends. Identifiers are always minted by the application. Records that cannot be read are
skipped and reported.** Parsing goes through the DOM.

Append won because the store is now a log. Events arrive from two directions — the generator over time
and each import — and both are additions to one history. Replacement would mean that opening a file
discards whatever the generator recorded overnight, which is not a trade anyone would choose if asked
plainly.

Minting every identifier won on the shape of the file. `time`, `text` and `severity` are what an event
*is*; an `id` is bookkeeping, and requiring a UUID in every record would make the sample file — itself
a deliverable someone reads — noise around the three fields that matter. It also removes a whole
category of failure: there is no such thing as an unreadable `id` any more, so a good record can never
be rejected over bookkeeping. An `id` key in a file is simply ignored, like any other unknown key.

The cost is real and is accepted with open eyes: **identity now belongs to the act of importing, not to
the event.** Importing the same file twice stores its events twice, because nothing distinguishes the
second import from new data. `insert or ignore` would be theatre here — with minted keys there is
nothing to collide — so the insert is plain and the duplication is honest rather than hidden. If
de-duplication is ever wanted, it needs a decision about what makes two events the same, which is a
different ADR.

Two failure modes, two mechanisms:

- **The file is unusable** — cannot be read, is not valid JSON, or its root is not an array. There is
  nothing to return, so `EEventImportError` is raised with the file name in the message and the stored
  history is untouched.
- **A record is unusable** — not an object, or missing or unreadable `time`, `text` or `severity`. It is
  skipped, counted, and the first problem is kept so the message says something the user can act on.

What counts as unusable is deliberately narrow. `severity` is matched case-insensitively against the
same `SeverityNames` the rest of the application uses, so `ERROR` and `error` both pass while `Critical`
does not: an unknown level rejects the record rather than silently becoming `Info`, because guessing at
severity is worse than admitting the record is broken. `time` must parse as the ISO 8601 form from ADR
0006. Unknown keys are ignored.

Three sample files ship rather than one, because a claim about withstanding bad input is worth being
able to demonstrate: `sample-events.json` is the good file the statement asks for,
`sample-events-invalid.json` is valid JSON whose records are broken in six different ways, and
`sample-events-malformed.json` is not valid JSON at all.

## Consequences

Easier: writing a file by hand, which now needs three keys per record and no identifiers; importing
real files, which are rarely perfect; demonstrating the robustness requirement, which is something to
click rather than a claim in a README. The confirmation prompt also disappears, because nothing is
destroyed and so there is nothing to confirm.

Harder: re-importing is not idempotent, and no warning can be given at the time, because the
application cannot tell that it has seen these events before. A user who clicks Import twice gets
everything twice, and the only remedy is deleting the database.

To revisit if the assumptions change: a request to de-duplicate, which would need a definition of
sameness — probably the triple of time, text and severity — and would turn the insert into an upsert
against a unique index rather than the primary key; files large enough that holding the DOM matters;
or a requirement to report every problem rather than the first.

The consequence to watch: nothing removes events any more. The database only grows, and the only route
back to empty is deleting the file named in ADR 0005. That belongs in the README beside the path rather
than being left for a user to work out.
