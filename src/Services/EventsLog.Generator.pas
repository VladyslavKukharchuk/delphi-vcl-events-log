unit EventsLog.Generator;

interface

uses
  System.Classes, System.SyncObjs, EventsLog.Event;

const
  DefaultInterval = 1000;

type
  TEventProducedProc = reference to procedure(const AEvent: TLogEvent);
  TEventGenerator = class(TThread)
  private
    FOnProduced: TEventProducedProc;
    FInterval: Cardinal;
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
  TEventTemplate = record
    Text: string;
    Severity: TEventSeverity;
  end;

const
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
  FOnProduced := AOnProduced;
  FInterval := AInterval;
  FStopping := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TEventGenerator.Destroy;
begin
  inherited;
  FStopping.Free;
end;

procedure TEventGenerator.TerminatedSet;
begin
  FStopping.SetEvent;
end;

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
    if FStopping.WaitFor(FInterval) = wrSignaled then
      Break;
  end;
end;

end.
