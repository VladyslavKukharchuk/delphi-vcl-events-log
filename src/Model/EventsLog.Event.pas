unit EventsLog.Event;

interface

type
  TEventSeverity = (esInfo, esWarning, esError);

  TLogEvent = record
  private
    FId: TGUID;
    FTime: TDateTime;
    FText: string;
    FSeverity: TEventSeverity;
  public
    constructor Create(const AId: TGUID; ATime: TDateTime; const AText: string;
      ASeverity: TEventSeverity);
    class function New(ATime: TDateTime; const AText: string;
      ASeverity: TEventSeverity): TLogEvent; static;
    property Id: TGUID read FId;
    property Time: TDateTime read FTime;
    property Text: string read FText;
    property Severity: TEventSeverity read FSeverity;
  end;

const
  SeverityNames: array[TEventSeverity] of string = ('Info', 'Warning', 'Error');

function SeverityToStr(ASeverity: TEventSeverity): string;
function TryStrToSeverity(const AValue: string; out ASeverity: TEventSeverity): Boolean;

{ Canonical UUID text, without the braces Delphi puts around it (ADR 0006). }
function GuidToText(const AId: TGUID): string;
function TryTextToGuid(const AValue: string; out AId: TGUID): Boolean;

implementation

uses
  System.SysUtils;

{ TLogEvent }

constructor TLogEvent.Create(const AId: TGUID; ATime: TDateTime; const AText: string;
  ASeverity: TEventSeverity);
begin
  FId := AId;
  FTime := ATime;
  FText := AText;
  FSeverity := ASeverity;
end;

class function TLogEvent.New(ATime: TDateTime; const AText: string;
  ASeverity: TEventSeverity): TLogEvent;
begin
  Result := TLogEvent.Create(TGUID.NewGuid, ATime, AText, ASeverity);
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

function GuidToText(const AId: TGUID): string;
begin
  Result := Copy(AId.ToString, 2, 36);
end;

function TryTextToGuid(const AValue: string; out AId: TGUID): Boolean;
var
  Braced: string;
begin
  Braced := Trim(AValue);
  if (Braced <> '') and (Braced[1] <> '{') then
    Braced := '{' + Braced + '}';
  try
    AId := StringToGUID(Braced);
    Result := True;
  except
    on EConvertError do
      Result := False;
  end;
end;

end.
