# 0011. The generator is a thread that exists only while it runs

- **Status:** accepted
- **Date:** 2026-08-21

## Context

The statement asks for a generator that can be switched on and off, that appends one random event a
second while it is on, and that runs on a background thread without blocking the window.

The threading model itself was already decided. [ADR 0007](0007-event-repository.md) put the database
connection on the main thread and had the generator hand each event over with `TThread.Queue`, because
that hop has to happen anyway to repaint the table; it also said refreshes are coalesced, since every
refresh costs a query. So this decision is not about which thread owns what. What is left is smaller
and still worth recording: when the thread exists, how it waits out its second, what "coalesced" is in
code, what a random event looks like, and what the window does when events arrive under the user's
cursor.

Forces at play:

- Stopping must be immediate. A generator that finishes its current second before noticing is a window
  that hangs for up to a second on a click, and on shutdown that becomes a form that will not close.
- The interval is a second, so nothing here is a performance problem. Every option below costs
  nothing measurable; what differs is how much state a reader has to hold in their head.
- The insert happens on the main thread, so it can fail there — the disk fills, the file is locked —
  and it will fail again a second later, and a second after that.
- `src/Services` may not use `Vcl.*` or show a dialog (ADR 0001). `TThread` and `TEvent` are RTL, so
  the generator stays inside its layer; the window is what turns a failure into a message.

## Options

### When the thread exists

1. **Created on Start, destroyed on Stop.** Pro: "the generator is off" and "there is no thread" are
   the same statement, so `FGenerator = nil` is the whole of the state and the button cannot disagree
   with it. Pro: nothing runs while nothing is asked for. Con: a create and a destroy on every toggle.
2. **One thread for the lifetime of the form, paused by an event.** Pro: toggling is two calls on a
   `TEvent`. Con: a thread that is alive but idle, plus a second synchronisation object, and the state
   the window shows now lives in neither the thread's existence nor a field of the form but in whether
   an event object is signalled.
3. **A `TTimer` on the form and no thread at all.** Pro: the simplest code by a distance. Con: fails
   R9 outright — the work would run on the main thread, and the requirement is explicitly that
   generation does not.

### How the second is waited out

1. **`Sleep(1000)`.** Pro: one line. Con: uninterruptible. `Terminate` sets a flag the thread only
   reads when it wakes up, so a stop takes up to a second and a close takes up to a second longer.
2. **`TEvent.WaitFor(1000)`, signalled by `Terminate`.** Pro: the wait ends the moment it is asked to.
   Pro: `TerminatedSet` is the hook the RTL provides for exactly this, so the signal cannot be
   forgotten by a caller. Con: one more object to own and free.

### How the table keeps up

1. **Refresh on every arriving event.** Pro: no extra machinery. Con: one query per event, and a burst
   — a queue that piled up while the window was busy — becomes a query per item in it.
2. **A flag and a timer.** An arriving event marks the view stale; a 250 ms timer refreshes when it is.
   Pro: many events collapse into one query, and the delay is under what an eye registers. Pro: the
   timer runs only while the generator does. Con: two pieces of state instead of none.
3. **Invalidate the list and let it re-read.** Con: the list is virtual over the *result of a query*
   (D8), not over the log, so a repaint cannot show a row the query never returned.

### What a random event contains

1. **A random message and a random severity, drawn independently.** Con: reports "Application started"
   as an error one time in three. The table becomes nonsense to read, and nonsense is a poor
   demonstration of a table.
2. **A table of message-and-severity pairs, one drawn at random, with a number substituted into the
   message.** Pro: the log reads like a log, the severity filter has something meaningful to filter,
   and the number makes repeats distinguishable so a search finds one line rather than forty. Con: the
   distribution of severities is whatever the table happens to hold.

### What the window does when a generated event fails to store

1. **Let the exception surface.** Con: the same dialog every second, and the generator still running
   behind it. The application becomes unusable by the mechanism meant to report the problem.
2. **Stop the generator and report once.** Pro: the failure is stated, and the cause of the repetition
   is removed. Con: an `except` in the form, which needs the reason spelled out to stay honest.

### Auto-scroll while generating (D5)

1. **Scroll to the newest event.** Con: the list cannot be read while events arrive, because the
   position the reader chose is taken away from them once a second.
2. **Do not scroll.** The query is `order by time desc`, so the newest event appears at the top, which
   is where the list already is when it opens. There is nothing to scroll *to*.

## Decision

**The generator is a `TThread` created on Start and freed on Stop. It waits on a `TEvent` rather than
sleeping. Arriving events mark the view stale and a 250 ms timer refreshes it. Events are drawn from a
table of message-and-severity pairs. A failed insert stops the generator and is reported once. Nothing
scrolls.**

The lifetime won because it makes the state unforgeable: `FGenerator` is nil exactly when the generator
is off, so the button's caption is derived from one field rather than kept in step with a second one.
The cost — a thread created per toggle — is a few hundred microseconds on a control the user clicks by
hand.

Freeing the thread is the whole of stopping, and this is worth stating because the code looks too
short to be right: `TThread.Destroy` terminates the thread, and `Terminate` calls `TerminatedSet`,
which signals the event the thread is waiting on; then it waits for the thread to finish and drops
whatever the thread had queued but not yet run. So `FreeAndNil(FGenerator)` ends the loop, joins the
thread and cancels the callback, in that order, with no `WaitFor` of our own. The last event may be
dropped on the way out — stopping means stopping, and an event that arrives after the button says
"Start generating" would be a lie about what the application is doing.

`Queue` and not `Synchronize`, for a reason that is easy to get wrong: the main thread waits for this
thread while destroying it, so a thread blocking on the main thread would deadlock. Queue does not
block the generator, so the two never wait for each other.

The refresh timer is the concrete form of what ADR 0007 called coalescing. 250 ms is chosen to be
below the threshold where a delay reads as lag and far above the cost of the query; the timer is
enabled with the generator and disabled with it, and Stop flushes a pending refresh so the last event
is not left invisible.

Paired templates won on what the table is *for*. A reviewer opens this application to see a log; a log
whose severities contradict its messages demonstrates a random number generator, not an events log.
The number substituted into each message serves the search box, which otherwise finds forty identical
lines.

D5 is answered by the ordering rather than by a policy: newest first means new events arrive at the
top, where the list already is. A reader who has scrolled down keeps their place, and the rows under
their cursor shift by one for each event that arrives above them — the consequence of a log that grows
downward from the top, and the reason nothing here tries to preserve the selection.

## Consequences

Easier: everything about shutdown. Closing the window while generating stops the thread and waits for
it in one line, and the wait ends on the instant rather than at the end of the second.

Harder: the form now has a lifecycle to keep in order — the generator is stopped before the repository
is freed, because a queued event is stored on the main thread and would otherwise reach a repository
that is gone. `FormDestroy` says so, and that comment is the only thing standing between this design
and a crash on exit.

What to watch: the insert is still on the main thread, so an interval much shorter than a second, or a
database on a slow disk, would be felt in the window. ADR 0007 named that as the first thing to
revisit, and this decision does not change it — it only makes the trade visible once a second instead
of never.

To revisit if the assumptions change: an interval the user can set, which would make the argument
about the interval being a second worth re-examining; several generators at once, which would make one
`TEvent` per thread awkward and a producer queue the better shape; or a requirement to keep the
selected event under the cursor while the log grows, which is a different job than not scrolling.
