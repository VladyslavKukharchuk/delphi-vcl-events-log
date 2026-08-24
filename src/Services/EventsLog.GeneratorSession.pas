unit EventsLog.GeneratorSession;

interface

uses
  EventsLog.Event, EventsLog.EventRepository, EventsLog.Generator;

type
  { The generator's lifetime, plus the two things its callback is not allowed to
    do from inside itself: stop the thread and talk to the user (ADR 0012). It
    owns the thread, stores what the thread produces, and holds the answers the
    caller comes back for - whether there is something new to show, and whether
    storing failed.

    There is no Vcl.* here, and that is the point: the part of generating that
    is easy to get wrong has nothing to do with controls. }
  TGeneratorSession = class
  private
    FRepository: IEventRepository;
    FInterval: Cardinal;
    { Nil exactly when the session is not running, so the caption of a button
      has no second copy of that state to keep in step with (ADR 0011). }
    FGenerator: TEventGenerator;
    FStale: Boolean;
    FProblem: string;
    procedure EventArrived(const AEvent: TLogEvent);
  public
    { The interval is a parameter so a test does not have to wait out a whole
      second for each event it wants to see (ADR 0013). }
    constructor Create(const ARepository: IEventRepository;
      AInterval: Cardinal = DefaultInterval);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    function IsRunning: Boolean;
    { True when events have arrived since the last call, and clears that. The
      caller refreshes the view; a caller that is refreshing for its own reasons
      may call this to say the flag has been answered too. }
    function TakeStale: Boolean;
    { True when storing an event failed, and only the first time. Taking the
      problem stops the session, because a second later it would fail the same
      way and there is no use in saying so once a second. }
    function TakeProblem(out AMessage: string): Boolean;
  end;

implementation

uses
  System.SysUtils;

constructor TGeneratorSession.Create(const ARepository: IEventRepository;
  AInterval: Cardinal);
begin
  inherited Create;
  FRepository := ARepository;
  FInterval := AInterval;
end;

destructor TGeneratorSession.Destroy;
begin
  Stop;
  inherited;
end;

procedure TGeneratorSession.Start;
begin
  if FGenerator <> nil then
    Exit;
  FGenerator := TEventGenerator.Create(EventArrived, FInterval);
end;

procedure TGeneratorSession.Stop;
begin
  { Freeing it is the whole of stopping: TThread.Destroy terminates the thread,
    waits for it, and drops the callback it had queued (ADR 0011). }
  FreeAndNil(FGenerator);
end;

function TGeneratorSession.IsRunning: Boolean;
begin
  Result := FGenerator <> nil;
end;

{ Runs on the main thread: the generator queues it there, so this is the same
  thread that owns the connection (ADR 0007). }
procedure TGeneratorSession.EventArrived(const AEvent: TLogEvent);
begin
  try
    FRepository.Insert(AEvent);
    FStale := True;
  except
    { Stopping here would run the thread's destructor from inside a callback of
      that same thread, which is a thread waiting for itself. The caller polls
      from outside the callback, so the caller stops the session. }
    on E: Exception do
      FProblem := E.Message;
  end;
end;

function TGeneratorSession.TakeStale: Boolean;
begin
  Result := FStale;
  FStale := False;
end;

function TGeneratorSession.TakeProblem(out AMessage: string): Boolean;
begin
  AMessage := FProblem;
  Result := FProblem <> '';
  FProblem := '';
  if Result then
    Stop;
end;

end.
