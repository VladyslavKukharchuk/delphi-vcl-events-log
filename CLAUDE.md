# CLAUDE.md

Working rules for this repository.

## Context

Test assignment for a Delphi Developer (Trainee / Junior) position — a VCL application called "Events Log".
Full statement: [docs/Test task Delphi Developer.docx](docs/Test%20task%20Delphi%20Developer.docx). The statement is the source of truth for scope: do not add features "just in case" and do not drop anything from the list of requirements.

## Environment

- RAD Studio 37.0 (`C:\Program Files (x86)\Embarcadero\Studio\37.0`), Personal edition.
- `EventsLog.dproj`: `ProjectVersion 20.3`, `FrameworkType VCL`, platforms Win32 + Win64 (Win64 is the default).
- Command-line build: `call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"` then `msbuild EventsLog.dproj /t:Build /p:Config=Release /p:Platform=Win32`.
- Standard RTL/VCL only. No third-party components or packages.

## Layout

```
EventsLog.dpr      entry point
Main.pas / .dfm    main form
docs/              assignment statement and supporting documents
docs/adr/          architecture decision records
```

- New units go next to `Main.pas` in the project root and must be added to the `.dpr` `uses` clause **with a relative path inside the repository**.
- Sample JSON data is kept in the repository (e.g. `sample-events.json`) — it is part of the assignment deliverables.

## Delphi code

- Embarcadero style: `PascalCase` for types (`TLogEvent`), `T` prefix for types and `I` for interfaces, `F` prefix for fields, 2-space indentation, `begin` on its own line.
- One unit, one responsibility: data model, JSON handling, event generator and the form never share a file.
- The form (`Main.pas`) only owns UI and wiring; business logic lives in separate units and knows nothing about visual controls.
- JSON goes through `System.JSON`. Parsing is always guarded: a malformed file or broken fields produce a clear message for the user instead of a raw `EJSONException`.
- Use `try..except` only where the error can actually be handled. Never silence exceptions with an empty `except end`.
- Release resources with `try..finally`; make ownership explicit (`TObjectList<T>` with `OwnsObjects`).
- Background work uses `TThread` (a descendant or `TThread.CreateAnonymousThread`). UI updates happen only via `TThread.Queue` / `Synchronize`. No `Application.ProcessMessages` as a substitute for a thread, and no busy waiting — pause with `TEvent.WaitFor` so shutdown is immediate.
- Guard the shared event list with a lock (`TCriticalSection` / `TMonitor`) while background generation is running.
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
