unit EventsLog.GeneratorSession.Tests;

interface

uses
  DUnitX.TestFramework;

type
  { The session is the only unit above the repository with no Vcl.* in it, which
    is what makes it reachable from a console runner at all (ADR 0013). It is
    tested against a fake repository rather than a real one: a real one needs a
    database file, and the two things worth checking here are not about SQL.
    They are that an arriving event is stored and marked, and that a store which
    fails stops the session and is reported exactly once. }
  [TestFixture]
  TGeneratorSessionTests = class
  public
    [Test]
    procedure StoresWhatTheGeneratorProduces;

    [Test]
    procedure AFailedStoreIsReportedOnceAndStopsTheSession;

    [Test]
    procedure StartAndStopAreIdempotent;

    [Test]
    procedure DestroyingARunningSessionReturns;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Diagnostics,
  EventsLog.Event, EventsLog.Filter, EventsLog.EventRepository,
  EventsLog.GeneratorSession;

const
  { Short enough that no test waits out the generator's real second, long enough
    that the thread is not spinning. }
  TestInterval = 20;
  { What is waited for takes one TestInterval; the rest is room for a loaded
    machine, because a timeout here has to mean "broken", not "busy". }
  TestTimeout = 3000;

type
  { Counts what it was asked to store, and fails on demand. Reference counted
    like the real repository, so a test that reads the counter must hold an
    IEventRepository of its own for as long as it does: without that reference
    the fake is destroyed the moment the session lets go of it. }
  TFakeRepository = class(TInterfacedObject, IEventRepository)
  private
    FStored: Integer;
    FFailWith: string;
  public
    constructor Create(const AFailWith: string = '');
    procedure Insert(const AEvent: TLogEvent);
    procedure InsertMany(const AEvents: TArray<TLogEvent>);
    procedure DeleteAll;
    function Query(const AFilter: TEventFilter): TArray<TLogEvent>;
    property Stored: Integer read FStored;
  end;

constructor TFakeRepository.Create(const AFailWith: string);
begin
  inherited Create;
  FFailWith := AFailWith;
end;

procedure TFakeRepository.Insert(const AEvent: TLogEvent);
begin
  if FFailWith <> '' then
    raise EEventRepositoryError.Create(FFailWith);
  Inc(FStored);
end;

procedure TFakeRepository.InsertMany(const AEvents: TArray<TLogEvent>);
var
  Event: TLogEvent;
begin
  for Event in AEvents do
    Insert(Event);
end;

procedure TFakeRepository.DeleteAll;
begin
  FStored := 0;
end;

function TFakeRepository.Query(const AFilter: TEventFilter): TArray<TLogEvent>;
begin
  Result := nil;
end;

{ The generator hands its event to the main thread with TThread.Queue, and that
  queue only moves when somebody calls CheckSynchronize. A VCL application does
  it from the message loop; a console runner has no message loop, so the test is
  what has to pump it. The condition is evaluated between pumps and therefore
  outside the queued callback, which is the same place the window's timer stands
  and the reason stopping the session from here is safe. }
function WaitUntil(const ACondition: TFunc<Boolean>): Boolean;
var
  Clock: TStopwatch;
begin
  Clock := TStopwatch.StartNew;
  repeat
    if ACondition then
      Exit(True);
    CheckSynchronize(10);
  until Clock.ElapsedMilliseconds > TestTimeout;
  Result := ACondition;
end;

{ TGeneratorSessionTests }

procedure TGeneratorSessionTests.StoresWhatTheGeneratorProduces;
var
  Fake: TFakeRepository;
  Repository: IEventRepository;
  Session: TGeneratorSession;
begin
  Fake := TFakeRepository.Create;
  { The interface reference keeps the fake alive; the object reference is only
    there to read the counter through. }
  Repository := Fake;
  Session := TGeneratorSession.Create(Repository, TestInterval);
  try
    Assert.IsFalse(Session.TakeStale, 'nothing has arrived before the start');
    Session.Start;
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := Fake.Stored > 0;
      end), 'the generator stored nothing within the timeout');
    { Stopped before the flag is read, so that no further event can arrive
      between the two reads below and make the second one flap. }
    Session.Stop;
    Assert.IsTrue(Session.TakeStale, 'a stored event must mark the view stale');
    Assert.IsFalse(Session.TakeStale, 'taking it twice must report nothing new');
  finally
    Session.Free;
  end;
end;

procedure TGeneratorSessionTests.AFailedStoreIsReportedOnceAndStopsTheSession;
var
  Fake: TFakeRepository;
  Repository: IEventRepository;
  Session: TGeneratorSession;
  Problem: string;
begin
  Fake := TFakeRepository.Create('the disk is full');
  Repository := Fake;
  Session := TGeneratorSession.Create(Repository, TestInterval);
  try
    Session.Start;
    { The condition takes the problem when there is one, so by the time this
      returns the message is in Problem and the session has stopped itself. }
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := Session.TakeProblem(Problem);
      end), 'a store that raised was never reported');
    Assert.AreEqual('the disk is full', Problem,
      'the reason has to reach the user unchanged');
    Assert.IsFalse(Session.IsRunning,
      'taking the problem must have stopped the session');
    Assert.IsFalse(Session.TakeProblem(Problem),
      'the problem must be reported once, not once an interval');
    Assert.AreEqual(0, Fake.Stored, 'nothing can have been stored');
  finally
    Session.Free;
  end;
end;

procedure TGeneratorSessionTests.StartAndStopAreIdempotent;
var
  Repository: IEventRepository;
  Session: TGeneratorSession;
begin
  Repository := TFakeRepository.Create;
  Session := TGeneratorSession.Create(Repository, TestInterval);
  try
    Assert.IsFalse(Session.IsRunning, 'a session that was never started');
    Session.Start;
    Assert.IsTrue(Session.IsRunning, 'Start must start it');
    Session.Start;
    Assert.IsTrue(Session.IsRunning, 'a second Start must be ignored, not fatal');
    Session.Stop;
    Assert.IsFalse(Session.IsRunning, 'Stop must stop it');
    Session.Stop;
    Assert.IsFalse(Session.IsRunning, 'a second Stop must be ignored, not fatal');
  finally
    Session.Free;
  end;
end;

{ What is asserted here is that this returns. Freeing a running session waits
  for the generator thread, and the point of the TEvent it waits on is that the
  wait ends at once instead of at the end of the interval (ADR 0011). A
  regression there does not fail an assertion, it hangs - so the elapsed time is
  checked as well, to turn a hang into a failure wherever it can still be
  measured. }
procedure TGeneratorSessionTests.DestroyingARunningSessionReturns;
var
  Repository: IEventRepository;
  Session: TGeneratorSession;
  Clock: TStopwatch;
begin
  Repository := TFakeRepository.Create;
  Session := TGeneratorSession.Create(Repository, TestInterval);
  Session.Start;
  Clock := TStopwatch.StartNew;
  Session.Free;
  Assert.IsTrue(Clock.ElapsedMilliseconds < TestTimeout,
    'freeing a running session should not have taken this long');
end;

initialization
  TDUnitX.RegisterTestFixture(TGeneratorSessionTests);

end.
