# 0005. The database file lives under %LOCALAPPDATA%

- **Status:** accepted
- **Date:** 2026-08-21

## Context

ADR 0004 puts the events in a SQLite database. That database is a file, and where a Windows desktop
application is allowed to put a file it writes to is not a matter of taste.

- Users receive a single `.exe` and may run it from anywhere, including `C:\Program Files\`. A
  standard user has no write permission there, so any location derived from the executable's own
  directory can fail at the first `INSERT` — and fail on the reviewer's machine rather than ours.
- The file grows. One event per second is 86,400 rows a day if the generator is left running, so the
  location has to be one where a growing file is expected.
- A reviewer has to be able to find it, look inside it and delete it to get a clean start. If the
  application's state is invisible, "it behaves oddly" has no remedy.
- More than one user account may exist on the machine.

## Options

### Option 1 — next to the executable

- Pro: portable. The whole application is one folder; copying it moves the data with it, and deleting
  the folder is a complete reset.
- Pro: obvious. Nobody has to be told where the data is.
- Con: fails outright under `C:\Program Files\` or any other read-only location, which is exactly
  where an installed application ends up.
- Con: on a shared machine every user writes to the same file, with whatever permissions the first
  one happened to create it with.

### Option 2 — `%APPDATA%` (Roaming)

`TPath.GetHomePath` — the conventional place for per-user application data.

- Pro: the standard location for user data, always writable.
- Pro: on a domain, settings follow the user between machines.
- Con: that roaming is the problem. A profile is copied at logon and logoff, and a growing event log
  is precisely the kind of file that must not be dragged across the network.

### Option 3 — `%LOCALAPPDATA%`

`TPath.GetCachePath`, which on Windows resolves through
`SHGetFolderPath(CSIDL_LOCAL_APPDATA)` — verified in the RTL source.

- Pro: the standard location for per-user data that is machine-local and may be large. Always
  writable, never roamed.
- Pro: each account gets its own log, which is the correct behaviour for per-user data.
- Con: less discoverable than a folder next to the executable, so the path has to be documented.
- Con: two users on one machine see different logs. Correct, but surprising if unstated.

### Option 4 — `C:\ProgramData`

- Pro: one shared log for every user of the machine.
- Con: needs write permissions granted at install time, and this application has no installer.
- Con: makes one user's events visible to another, which nothing here asks for.

### Option 5 — the user's `Documents`

- Pro: highly visible.
- Con: a database the application manages is not a document the user authored. `Documents` is a
  folder people curate, and putting working state there is the behaviour users complain about.

## Decision

`%LOCALAPPDATA%\EventsLog\events.db`, resolved as
`TPath.Combine(TPath.GetCachePath, 'EventsLog')` and created with `ForceDirectories` on first run.

Why it won: it is the only option that is always writable, never roamed and correct per user. Option 1
is the tempting one — it is simpler and trivially resettable — but it breaks in the single case that
matters most, an executable sitting in a directory the user cannot write to, and it breaks at runtime
rather than at startup. Option 2 is nearly right and fails on one detail, that a growing log has no
business in a roaming profile. Options 4 and 5 solve problems this application does not have.

The discoverability that Option 1 would have given is bought back with documentation instead: the
README states the exact path, and says that deleting that folder resets the application to empty.
That is the reviewer's reset switch and it needs to be written down, not inferred.

Portable mode — data beside the executable, chosen by a switch or by the absence of an installed
marker — is not implemented. It is a reasonable future feature and would be its own decision.

## Consequences

Easier: running the application from anywhere, including a read-only directory; keeping accounts on a
shared machine separate; letting the log grow without touching a roaming profile.

Harder: the application's state is no longer visible next to the executable, so both the README and
any bug report have to name the path. A user who copies the `.exe` to another machine does not bring
the data with it.

To revisit if the assumptions change: a request for portable operation, or a need for one shared log
across all users of a machine. Either would be a new ADR superseding this one.

The consequence to watch: the first run has to create the directory before opening the database, and
that is the one place where a failure is plausible in the field — an antivirus lock, a redirected
folder, a full disk. It fails with a message that names the path, rather than with a FireDAC error
about a file it could not open.
