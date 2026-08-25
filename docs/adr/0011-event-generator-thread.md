# 0011. The generator is a thread that exists only while it runs

- **Status:** accepted
- **Date:** 2026-08-21

## Context

The statement asks for a generator that can be switched on and off, appends one random event a second
while on, and runs on a background thread without blocking the window.

The threading model was already decided: [ADR 0007](0007-event-repository.md) put the connection on
the main thread and had the generator hand each event over with `TThread.Queue`, and said refreshes
are coalesced. What is left is smaller and still worth recording — when the thread exists, how it
waits out its second, what "coalesced" is in code, what a random event looks like, and what the
window does when events arrive under the user's cursor.

- Stopping must be immediate. A generator that finishes its current second before noticing is a
  window that hangs for up to a second on a click, and on shutdown a form that will not close.
- The interval is a second, so nothing here is a performance problem. What differs between the
  options is how much state a reader has to hold in their head.
- The insert happens on the main thread, so it can fail there — a full disk, a locked file — and it
  will fail again a second later, and a second after that.
- `src/Services` may not use `Vcl.*` or show a dialog (ADR 0001).

## Options

### When the thread exists

1. **Created on Start, destroyed on Stop.** Pro: "the generator is off" and "there is no thread" are
   the same statement, so `FGenerator = nil` is the whole of the state and the button cannot disagree
   with it. Con: a create and a destroy on every toggle.
2. **One thread for the lifetime of the form, paused by an event.** Pro: toggling is two calls. Con:
   a thread alive but idle, plus a second synchronisation object, and the state the window shows
   lives in neither the thread's existence nor a field of the form.
3. **A `TTimer` and no thread at all.** Con: fails the requirement outright — the work would run on
   the main thread.

### How the second is waited out

1. **`Sleep(1000)`.** Con: uninterruptible. A stop takes up to a second and a close a second longer.
2. **`TEvent.WaitFor(1000)`, signalled by `Terminate`.** Pro: the wait ends the moment it is asked
   to, and `TerminatedSet` is the hook the RTL provides for exactly this. Con: one more object to own.

### How the table keeps up

1. **Refresh on every arriving event.** Con: one query per event, and a burst becomes a query per
   item in it.
2. **A flag and a 250 ms timer.** Pro: many events collapse into one query, the delay is under what
   an eye registers, and the timer runs only while the generator does. Con: two pieces of state.
3. **Invalidate the list and let it re-read.** Con: the list is virtual over the *result of a query*,
   not over the log, so a repaint cannot show a row the query never returned.

### What a random event contains

1. **A random message and a random severity, drawn independently.** Con: reports "Application
   started" as an error one time in three; nonsense is a poor demonstration of a table.
2. **A table of message-and-severity pairs, with a number substituted into the message.** Pro: the
   log reads like a log, the severity filter has something meaningful to filter, and the number makes
   repeats distinguishable so a search finds one line rather than forty.

### What the window does when a generated event fails to store

Letting the exception surface means the same dialog every second with the generator still running
behind it. The alternative is to stop the generator and report once — the failure is stated and the
cause of the repetition removed, at the price of an `except` in the form.

## Decision

**The generator is a `TThread` created on Start and freed on Stop. It waits on a `TEvent` rather than
sleeping. Arriving events mark the view stale and a 250 ms timer refreshes it. Events are drawn from
a table of message-and-severity pairs. A failed insert stops the generator and is reported once.
Nothing scrolls.**

The lifetime won because it makes the state unforgeable: `FGenerator` is nil exactly when the
generator is off, so the button's caption derives from one field rather than being kept in step with
a second one. A thread per toggle is a few hundred microseconds on a control clicked by hand.

Freeing the thread is the whole of stopping, and this is worth stating because the code looks too
short to be right: `TThread.Destroy` terminates the thread, `Terminate` calls `TerminatedSet` which
signals the event the thread waits on, then it joins and drops whatever the thread had queued but not
yet run. So `FreeAndNil(FGenerator)` ends the loop, joins and cancels the callback, in that order,
with no `WaitFor` of our own. The last event may be dropped on the way out — an event arriving after
the button says "Start generating" would be a lie about what the application is doing.

`Queue` and not `Synchronize`, for a reason easy to get wrong: the main thread waits for this thread
while destroying it, so a thread blocking on the main thread would deadlock.

Paired templates won on what the table is *for*. A reviewer opens this application to see a log; a
log whose severities contradict its messages demonstrates a random number generator.

Nothing scrolls because the query is `order by time desc`: the newest event appears at the top, which
is where the list already is when it opens. There is nothing to scroll *to*, and a reader who has
scrolled down keeps their place.

## Consequences

Shutdown gains an order that has to be kept: the generator is stopped before the repository is freed,
because a queued event is stored on the main thread and would otherwise reach a repository that is
gone. This record is where that hazard starts; the full order it grew into is written out in
[ADR 0013](0013-repository-interface-and-composition-root.md). The insert is also still on the main
thread, so an interval much shorter than a second, or a database on a slow disk, would be felt in the
window.
