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
  IsoTimeFormat = 'yyyy-mm-dd"T"hh:nn:ss.zzz';

function SeverityToStr(ASeverity: TEventSeverity): string;
function TryStrToSeverity(const AValue: string; out ASeverity: TEventSeverity): Boolean;

{ Canonical UUID text, without the braces Delphi puts around it (ADR 0006). }
function GuidToText(const AId: TGUID): string;
function TryTextToGuid(const AValue: string; out AId: TGUID): Boolean;

{ ISO 8601 in local time, fixed width, so that ordering the text orders the
  events (ADR 0006). }
function TimeToText(ATime: TDateTime): string;
function TryTextToTime(const AValue: string; out ATime: TDateTime): Boolean;

implementation

uses
  System.SysUtils, System.DateUtils;

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

function TimeToText(ATime: TDateTime): string;
begin
  { Invariant settings on purpose: FormatDateTime substitutes the locale's time
    separator for ':', so the stored format would follow whatever machine wrote
    the row. }
  Result := FormatDateTime(IsoTimeFormat, ATime, TFormatSettings.Invariant);
end;

function TryTextToTime(const AValue: string; out ATime: TDateTime): Boolean;
var
  Year, Month, Day, Hour, Minute, Second, Milliseconds: Integer;
begin
  Result := False;
  if Length(AValue) < 19 then
    Exit;
  if not (TryStrToInt(Copy(AValue, 1, 4), Year)
    and TryStrToInt(Copy(AValue, 6, 2), Month)
    and TryStrToInt(Copy(AValue, 9, 2), Day)
    and TryStrToInt(Copy(AValue, 12, 2), Hour)
    and TryStrToInt(Copy(AValue, 15, 2), Minute)
    and TryStrToInt(Copy(AValue, 18, 2), Second)) then
    Exit;
  Milliseconds := 0;
  if (Length(AValue) >= 23) and not TryStrToInt(Copy(AValue, 21, 3), Milliseconds) then
    Exit;
  Result := TryEncodeDateTime(Year, Month, Day, Hour, Minute, Second,
    Milliseconds, ATime);
end;

end.
