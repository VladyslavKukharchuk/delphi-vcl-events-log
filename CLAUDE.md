# CLAUDE.md

Working rules for this repository.

## Context

Test assignment for a Delphi Developer (Trainee / Junior) position — a VCL application called "Events Log".
Full statement: [docs/Test task Delphi Developer.docx](docs/Test%20task%20Delphi%20Developer.docx). The statement is the source of truth for scope: do not add features "just in case" and do not drop anything from the list of requirements.

## Environment

- RAD Studio 37.0 (`C:\Program Files (x86)\Embarcadero\Studio\37.0`), Personal edition.
- `EventsLog.dproj`: `ProjectVersion 20.3`, `FrameworkType VCL`, platforms Win32 + Win64 (Win64 is the default).
- Command-line build: `call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"` then `msbuild EventsLog.dproj /t:Build /p:Config=Release /p:Platform=Win32`.
- Standard RTL/VCL plus FireDAC for data access, per [ADR 0004](docs/adr/0004-sqlite-for-local-persistence.md). No third-party components or packages. SQLite is linked statically through `FireDAC.Phys.SQLiteWrapper.Stat`, so the executable ships with no DLL beside it.

## Layout

```
EventsLog.dpr      entry point and composition root
src/Model/         entities, event store, filtering — knows about neither VCL nor JSON
src/Repository/    data access — JSON import and the SQLite store
src/Services/      background work (event generator)
src/UI/            Main.pas / .dfm — the form and its wiring
tests/             DUnitX test project and the sample JSON files
docs/              assignment statement and supporting documents
docs/adr/          architecture decision records
```

The layer folders are the structure decided in [ADR 0001](docs/adr/0001-layer-folders-under-src.md).

- Unit names stay short — `EventsLog.Store.pas`, not `EventsLog.Model.Store.pas`. The folder carries the layer, the name carries the role.
- A new unit goes into the folder of its layer and is added to the `.dpr` `uses` clause **with a relative path inside the repository**: `EventsLog.Store in 'src\Model\EventsLog.Store.pas'`.
- Dependencies point one way: `src/UI` → `src/Services` → `src/Repository` → `src/Model`. Nothing in `src/Model` may reference another layer, and no unit outside `src/UI` may use `Vcl.*` or show a dialog — errors travel out as results or exceptions.
- A new layer folder also goes into the search path in `EventsLog.dproj` (`DCC_UnitSearchPath`, i.e. **Project → Options → Building → Delphi Compiler → Search path**).
- Sample JSON data lives in `tests/` next to the tests that use it as fixtures (`sample-events.json`, plus one file with broken records and one that is not JSON). It is part of the assignment deliverables as well as of the test suite.
- Tests are DUnitX, built from `tests/EventsLogTests.dproj` and run from the IDE. Personal edition refuses command-line compiling, so there is no CI and no `msbuild` path for them.

## Delphi code

- Embarcadero style: `PascalCase` for types (`TLogEvent`), `T` prefix for types and `I` for interfaces, `F` prefix for fields, 2-space indentation, `begin` on its own line.
- One unit, one responsibility: data model, JSON handling, event generator and the form never share a file.
- The form (`src/UI/Main.pas`) only owns UI and wiring; business logic lives in separate units and knows nothing about visual controls.
- No `TDataSet` leaves `src/Repository`: a query turns rows into `TLogEvent` values before returning them, so no dataset reaches the model or the form.
- JSON goes through `System.JSON`. Parsing is always guarded: a malformed file or broken fields produce a clear message for the user instead of a raw `EJSONException`.
- Use `try..except` only where the error can actually be handled. Never silence exceptions with an empty `except end`.
- Release resources with `try..finally`; make ownership explicit (`TObjectList<T>` with `OwnsObjects`).
- Background work uses `TThread` (a descendant or `TThread.CreateAnonymousThread`). UI updates happen only via `TThread.Queue` / `Synchronize`. No `Application.ProcessMessages` as a substitute for a thread, and no busy waiting — pause with `TEvent.WaitFor` so shutdown is immediate.
- There is no shared event list to guard: the generator builds an event on its own thread and hands it to the UI thread with `TThread.Queue`, and only that thread writes to the database or to the array behind the table ([ADR 0007](docs/adr/0007-event-repository.md)). If a design ever does share mutable state between threads, guard it with a lock (`TCriticalSection` / `TMonitor`).
- Comments only where the code does not explain itself.

## Documentation

- All documentation in this repository is written in English: `README.md`, `CLAUDE.md`, ADRs, code comments, and any file under `docs/`.
- `README.md` must contain, per the assignment: the Delphi version, a short description of the program structure, and a list of what could be improved given more time. Keep it updated alongside the code, not at the last minute.

## Architecture decision records

Every key technical decision is recorded as an ADR in `docs/adr/`. A decision is "key" when it is hard to reverse later or when a reasonable reviewer could ask "why this way?" — for example the grid control choice, the JSON parsing strategy, the threading model, or the in-memory data structure. Small local choices do not need an ADR.

- File name: `NNNN-short-title.md`, sequential number starting at `0001` (e.g. `0001-use-tlistview-for-event-table.md`).
- Use [docs/adr/0000-template.md](docs/adr/0000-template.md) as the starting point.
- Each ADR must state:
  - **Context** — the problem being solved and the constraints that shape it.
  - **Options** — the alternatives considered, each with its pros and cons.
  - **Decision** — the option chosen and why it won over the others.
- ADRs are append-only: an existing record is never rewritten. When a decision changes, add a new ADR, mark the old one as superseded and link the two.
- Write the ADR in the same commit or pull request as the change it describes.

## Git

- Never work directly on `main`: use a `feat/*`, `fix/*` or `docs/*` branch and open a pull request.
- Commit messages in English, imperative mood: `Add event model and JSON import`.
- Never commit build artifacts (`Win32/`, `Win64/`, `*.dcu`, `*.exe`) or IDE state (`__history/`, `__recovery/`, `*.local`, `*.dsk`, `*.identcache`). `.gitignore` already covers this — update it instead of adding manual exceptions.
- After working in the IDE, review `.dproj` with `git diff`: the IDE injects noise into it (`DeployFile` entries for random files, a disappearing `<FormType>dfm</FormType>`). Keep that noise out of commits.
- The built `.exe` is part of the deliverables, but it ships as a release artifact rather than a commit on a branch.

## Communication

- Before implementing a new block of functionality, outline the plan briefly and wait for confirmation.
