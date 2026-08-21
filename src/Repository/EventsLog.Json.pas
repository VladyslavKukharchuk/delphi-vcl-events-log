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
  SNotText = 'record %d has a %s that is not text: %s';
  SBadTime = 'record %d has an unusable time, the %s is wrong: %s';
  SBadSeverity = 'record %d has an unknown severity: %s';

{ TImportReport }

constructor TImportReport.Create(AAccepted, ARejected: Integer;
  const AFirstProblem: string);
begin
  FAccepted := AAccepted;
  FRejected := ARejected;
  FFirstProblem := AFirstProblem;
end;

{ A key that is absent and a key holding the wrong kind of value are different
  mistakes, and saying so is the difference between a message that helps and one
  that misleads. Values[] returns nil for an absent key. }
function TryReadText(AItem: TJSONObject; AIndex: Integer; const AName: string;
  out AText: string; out AProblem: string): Boolean;
var
  Node: TJSONValue;
begin
  Result := False;
  Node := AItem.Values[AName];
  if Node = nil then
  begin
    AProblem := Format(SMissingField, [AIndex, AName]);
    Exit;
  end;
  if not (Node is TJSONString) then
  begin
    AProblem := Format(SNotText, [AIndex, AName, Node.ToJSON]);
    Exit;
  end;
  AText := Node.Value;
  Result := True;
end;

function TryElementToEvent(AElement: TJSONValue; AIndex: Integer;
  out AEvent: TLogEvent; out AProblem: string): Boolean;
var
  Item: TJSONObject;
  EventTime: TDateTime;
  Raw, EventText: string;
  Severity: TEventSeverity;
  TimeProblem: Integer;
begin
  Result := False;
  if not (AElement is TJSONObject) then
  begin
    AProblem := Format(SNotAnObject, [AIndex]);
    Exit;
  end;
  Item := TJSONObject(AElement);

  if not TryReadText(Item, AIndex, 'time', Raw, AProblem) then
    Exit;
  if not TryTextToTime(Raw, EventTime, TimeProblem) then
  begin
    AProblem := Format(SBadTime,
      [AIndex, TimeProblemToStr(TimeProblem), Raw]);
    Exit;
  end;

  if not TryReadText(Item, AIndex, 'text', EventText, AProblem) then
    Exit;

  if not TryReadText(Item, AIndex, 'severity', Raw, AProblem) then
    Exit;
  if not TryStrToSeverity(Raw, Severity) then
  begin
    AProblem := Format(SBadSeverity, [AIndex, Raw]);
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
