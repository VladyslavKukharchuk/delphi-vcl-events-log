unit EventsLog.Json;

interface

uses
  System.SysUtils, EventsLog.Event;

type
  { The file itself is unusable: unreadable, not JSON, or not an array of
    events. Nothing can be salvaged, so this is raised rather than reported. }
  EEventImportError = class(Exception);

  { What a usable file contained. Rejected records are counted rather than
    fatal, and the first problem is kept so the user learns something more
    useful than a number. }
  TImportReport = record
  private
    FAccepted: Integer;
    FRejected: Integer;
    FFirstProblem: string;
  public
    constructor Create(AAccepted, ARejected: Integer; const AFirstProblem: string);
    property Accepted: Integer read FAccepted;
    property Rejected: Integer read FRejected;
    property FirstProblem: string read FFirstProblem;
  end;

function LoadEventsFromFile(const AFileName: string;
  out AReport: TImportReport): TArray<TLogEvent>;

implementation

uses
  System.IOUtils, System.JSON, System.Generics.Collections;

resourcestring
  SCannotRead = 'Cannot read %s.' + sLineBreak + '%s';
  SNotJson = '%s is not valid JSON.';
  SNotArray = '%s does not contain a JSON array of events.';
  SNotAnObject = 'record %d is not a JSON object';
  SMissingField = 'record %d has no %s';
  SBadField = 'record %d has an unusable %s: %s';

{ TImportReport }

constructor TImportReport.Create(AAccepted, ARejected: Integer;
  const AFirstProblem: string);
begin
  FAccepted := AAccepted;
  FRejected := ARejected;
  FFirstProblem := AFirstProblem;
end;

function TryElementToEvent(AElement: TJSONValue; AIndex: Integer;
  out AEvent: TLogEvent; out AProblem: string): Boolean;
var
  Item: TJSONObject;
  EventTime: TDateTime;
  Raw, EventText: string;
  Severity: TEventSeverity;
begin
  Result := False;
  if not (AElement is TJSONObject) then
  begin
    AProblem := Format(SNotAnObject, [AIndex]);
    Exit;
  end;
  Item := TJSONObject(AElement);

  if not Item.TryGetValue<string>('time', Raw) then
  begin
    AProblem := Format(SMissingField, [AIndex, 'time']);
    Exit;
  end;
  if not TryTextToTime(Raw, EventTime) then
  begin
    AProblem := Format(SBadField, [AIndex, 'time', Raw]);
    Exit;
  end;

  if not Item.TryGetValue<string>('text', EventText) then
  begin
    AProblem := Format(SMissingField, [AIndex, 'text']);
    Exit;
  end;

  if not Item.TryGetValue<string>('severity', Raw) then
  begin
    AProblem := Format(SMissingField, [AIndex, 'severity']);
    Exit;
  end;
  if not TryStrToSeverity(Raw, Severity) then
  begin
    AProblem := Format(SBadField, [AIndex, 'severity', Raw]);
    Exit;
  end;

  { The file carries no identity: identifiers are minted here (ADR 0009). }
  AEvent := TLogEvent.New(EventTime, EventText, Severity);
  Result := True;
end;

function LoadEventsFromFile(const AFileName: string;
  out AReport: TImportReport): TArray<TLogEvent>;
var
  Content: string;
  Root: TJSONValue;
  Events: TList<TLogEvent>;
  Event: TLogEvent;
  Index, Rejected: Integer;
  Problem, FirstProblem: string;
begin
  try
    Content := TFile.ReadAllText(AFileName, TEncoding.UTF8);
  except
    { Any failure to read means the same thing to the caller: this file cannot
      be imported. }
    on E: Exception do
      raise EEventImportError.CreateFmt(SCannotRead, [AFileName, E.Message]);
  end;

  { ParseJSONValue returns nil for invalid JSON instead of raising, which is
    exactly the guarded behaviour we want here. }
  Root := TJSONObject.ParseJSONValue(Content);
  if Root = nil then
    raise EEventImportError.CreateFmt(SNotJson, [AFileName]);
  try
    if not (Root is TJSONArray) then
      raise EEventImportError.CreateFmt(SNotArray, [AFileName]);

    Rejected := 0;
    FirstProblem := '';
    Events := TList<TLogEvent>.Create;
    try
      for Index := 0 to TJSONArray(Root).Count - 1 do
        if TryElementToEvent(TJSONArray(Root).Items[Index], Index + 1, Event,
          Problem) then
          Events.Add(Event)
        else
        begin
          Inc(Rejected);
          if FirstProblem = '' then
            FirstProblem := Problem;
        end;
      Result := Events.ToArray;
    finally
      Events.Free;
    end;
    AReport := TImportReport.Create(Length(Result), Rejected, FirstProblem);
  finally
    Root.Free;
  end;
end;

end.
