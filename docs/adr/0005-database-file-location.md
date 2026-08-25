# 0005. The database file lives under %LOCALAPPDATA%

- **Status:** accepted
- **Date:** 2026-08-21

## Context

ADR 0004 puts the events in a SQLite database. That database is a file, and where a Windows desktop
application may put a file it writes to is not a matter of taste.

- Users receive a single `.exe` and may run it from anywhere, including `C:\Program Files\`, where a
  standard user has no write permission.
- The file grows: one event per second is 86,400 rows a day if the generator is left running.
- A reviewer has to be able to find it, look inside it and delete it to get a clean start.
- More than one user account may exist on the machine.

`C:\ProgramData` and the user's `Documents` are out from the start — the first needs permissions
granted at install time and this application has no installer, and the second is a folder people
curate, not a place for working state.

## Options

### Option 1 — next to the executable

- Pro: portable and obvious. Copying the folder moves the data; deleting it is a complete reset.
- Con: fails outright under `C:\Program Files\` — and fails at the first `insert`, on the reviewer's
  machine rather than ours.
- Con: on a shared machine every user writes to the same file.

### Option 2 — `%APPDATA%` (Roaming), via `TPath.GetHomePath`

- Pro: the standard location for user data, always writable; on a domain it follows the user.
- Con: that roaming is the problem. A profile is copied at logon and logoff, and a growing event log
  is precisely the kind of file that must not be dragged across the network.

### Option 3 — `%LOCALAPPDATA%`, via `TPath.GetCachePath`

Resolves through `SHGetFolderPath(CSIDL_LOCAL_APPDATA)` — verified in the RTL source.

- Pro: the standard location for per-user data that is machine-local and may be large. Always
  writable, never roamed, and each account gets its own log.
- Con: less discoverable than a folder beside the executable, so the path has to be documented.

## Decision

`%LOCALAPPDATA%\EventsLog\events.db`, resolved as `TPath.Combine(TPath.GetCachePath, 'EventsLog')`
and created with `ForceDirectories` on first run.

It is the only option that is always writable, never roamed and correct per user. Option 1 is the
tempting one — simpler and trivially resettable — but it breaks in the single case that matters most,
an executable in a directory the user cannot write to, and it breaks at runtime rather than at
startup. Option 2 is nearly right and fails on one detail.

The discoverability Option 1 would have given is bought back with documentation: the README states
the exact path and says that deleting the folder resets the application to empty. That is the
reviewer's reset switch and it needs to be written down, not inferred. Portable mode — data beside
the executable, behind a switch — is not implemented and would be its own decision.

## Consequences

The first run has to create the directory before opening the database, and that is the one place
where a failure is plausible in the field: an antivirus lock, a redirected folder, a full disk. It
fails with a message that names the path, rather than with a FireDAC error about a file it could not
open.
