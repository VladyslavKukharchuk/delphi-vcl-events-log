unit EventsLog.Generator;

interface

uses
  System.Classes, System.SyncObjs, EventsLog.Event;

const
  DefaultInterval = 1000;

type
  { What the generator does with a finished event. It is called on the main
    thread, because the generator queues it there: whoever supplies it may
    touch the database or the window without a second thought about threads
    (ADR 0007). }
  TEventProducedProc = reference to procedure(const AEvent: TLogEvent);

  { Produces one random event every interval until it is told to stop. It holds
    nothing the rest of the application reads, so there is no shared state to
    guard: the event travels to the main thread as a value. }
  TEventGenerator = class(TThread)
  private
    FOnProduced: TEventProducedProc;
    FInterval: Cardinal;
    { Signalled by Terminate, so a stop does not have to wait out the interval
      that is already running. }
    FStopping: TEvent;
    procedure Publish(const AEvent: TLogEvent);
  protected
    procedure Execute; override;
    procedure TerminatedSet; override;
  public
    constructor Create(const AOnProduced: TEventProducedProc;
      AInterval: Cardinal = DefaultInterval);
    destructor Destroy; override;
  end;

implementation

uses
  System.SysUtils;

type
  { A message and the level it would be reported at. The two are paired rather
    than drawn separately, because a random pair would report "Application
    started" as an error and the table is meant to be readable. }
  TEventTemplate = record
    Text: string;
    Severity: TEventSeverity;
  end;

const
  { The number stands in for the detail a real log line would carry, so
    repeated events differ and searching for one of them finds one of them.
    A template holds no per cent sign, since Format reads it as a placeholder. }
  EventTemplates: array[0..11] of TEventTemplate = (
    (Text: 'Worker %d finished its batch'; Severity: esInfo),
    (Text: 'Configuration reloaded, %d settings applied'; Severity: esInfo),
    (Text: 'User session %d opened'; Severity: esInfo),
    (Text: 'Cache warmed with %d entries'; Severity: esInfo),
    (Text: 'Scheduled job %d completed'; Severity: esInfo),
    (Text: 'Request took %d ms, over the expected budget'; Severity: esWarning),
    (Text: 'Retrying the report service, attempt %d'; Severity: esWarning),
    (Text: 'Queue has grown to %d pending items'; Severity: esWarning),
    (Text: 'Session %d expired before it was used'; Severity: esWarning),
    (Text: 'Connection %d refused by the reporting service'; Severity: esError),
    (Text: 'Writing the daily summary failed after %d attempts'; Severity: esError),
    (Text: 'Worker %d stopped with an unhandled error'; Severity: esError));

  TemplateDetailRange = 1000;

{ Random is not thread safe, because RandSeed is global. Only this thread ever
  calls it: the window has nothing random to do. }
function RandomEvent: TLogEvent;
var
  Template: TEventTemplate;
begin
  Template := EventTemplates[Random(Length(EventTemplates))];
  Result := TLogEvent.New(Now, Format(Template.Text, [Random(TemplateDetailRange)]),
    Template.Severity);
end;

{ TEventGenerator }

constructor TEventGenerator.Create(const AOnProduced: TEventProducedProc;
  AInterval: Cardinal);
begin
  { Every field is in place before the thread exists, so Execute cannot reach
    one that is not, and TerminatedSet cannot signal an event that has not been
    created yet. Suspended and then started for the same reason. }
  FOnProduced := AOnProduced;
  FInterval := AInterval;
  FStopping := TEvent.Create(nil, True, False, '');
  inherited Create(True);
  Start;
end;

destructor TEventGenerator.Destroy;
begin
  { inherited is the whole of stopping: TThread.Destroy terminates the thread —
    which signals FStopping through TerminatedSet — waits for it, and then drops
    whatever callback was queued but never run. An event queued a moment before
    a stop would otherwise call back into an owner on its way out. }
  inherited;
  FStopping.Free;
end;

procedure TEventGenerator.TerminatedSet;
begin
  FStopping.SetEvent;
end;

{ Queue rather than Synchronize: the caller of Terminate waits for this thread,
  and a thread that blocks on the waiting thread would deadlock. The locals are
  captured by value, so the closure survives without reading this object. }
procedure TEventGenerator.Publish(const AEvent: TLogEvent);
var
  Produced: TEventProducedProc;
  Event: TLogEvent;
begin
  Produced := FOnProduced;
  Event := AEvent;
  TThread.Queue(Self,
    procedure
    begin
      Produced(Event);
    end);
end;

procedure TEventGenerator.Execute;
begin
  NameThreadForDebugging('EventsLog generator');
  Randomize;
  while not Terminated do
  begin
    Publish(RandomEvent);
    { Waiting rather than sleeping: Terminate signals the event, so shutdown is
      immediate instead of up to one interval late. }
    if FStopping.WaitFor(FInterval) = wrSignaled then
      Break;
  end;
end;

end.
