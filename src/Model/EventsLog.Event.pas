unit EventsLog.Event;

interface

type
  TEventSeverity = (esInfo, esWarning, esError);

  TLogEvent = record
  private
    FId: TGUID;
    FTimestamp: TDateTime;
    FText: string;
    FSeverity: TEventSeverity;
  public
    constructor Create(const AId: TGUID; ATimestamp: TDateTime; const AText: string;
      ASeverity: TEventSeverity);
    class function New(ATimestamp: TDateTime; const AText: string;
      ASeverity: TEventSeverity): TLogEvent; static;
    property Id: TGUID read FId;
    property Timestamp: TDateTime read FTimestamp;
    property Text: string read FText;
    property Severity: TEventSeverity read FSeverity;
  end;

const
  SeverityNames: array[TEventSeverity] of string = ('Info', 'Warning', 'Error');

function SeverityToStr(ASeverity: TEventSeverity): string;
function TryStrToSeverity(const AValue: string; out ASeverity: TEventSeverity): Boolean;

implementation

uses
  System.SysUtils;

{ TLogEvent }

constructor TLogEvent.Create(const AId: TGUID; ATimestamp: TDateTime; const AText: string;
  ASeverity: TEventSeverity);
begin
  FId := AId;
  FTimestamp := ATimestamp;
  FText := AText;
  FSeverity := ASeverity;
end;

class function TLogEvent.New(ATimestamp: TDateTime; const AText: string;
  ASeverity: TEventSeverity): TLogEvent;
begin
  Result := TLogEvent.Create(TGUID.NewGuid, ATimestamp, AText, ASeverity);
end;

function SeverityToStr(ASeverity: TEventSeverity): string;
begin
  Result := SeverityNames[ASeverity];
end;

function TryStrToSeverity(const AValue: string; out ASeverity: TEventSeverity): Boolean;
var
  Severity: TEventSeverity;
begin
  for Severity := Low(TEventSeverity) to High(TEventSeverity) do
    if SameText(AValue, SeverityNames[Severity]) then
    begin
      ASeverity := Severity;
      Result := True;
      Exit;
    end;
  Result := False;
end;

end.
