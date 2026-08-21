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
  events (ADR 0006). Reading goes through the RTL parser, which understands a Z
  or an offset; writing does not emit either, so the stored form stays fixed
  width and local. }
function TimeToText(ATime: TDateTime): string;
function TryTextToTime(const AValue: string; out ATime: TDateTime): Boolean; overload;
function TryTextToTime(const AValue: string; out ATime: TDateTime;
  out AProblem: Integer): Boolean; overload;
{ Names the field TryTextToTime rejected, for a message worth reading. }
function TimeProblemToStr(AProblem: Integer): string;

implementation

uses
  System.SysUtils, System.DateUtils;

const
  { The error codes TryISO8601ToDate reports, in its order. }
  TimeProblemNames: array[1..9] of string = ('week', 'month', 'year', 'day',
    'hour', 'minute', 'second', 'time zone', 'milliseconds');
  { Anything the parser raises on rather than reports, which it has no code for. }
  TimeProblemUnknown = 0;

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
  { The RTL has no Try variant for GUIDs, so the exception is the only signal
    available and converting it here is the point of this function. }
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
    the row. DateToISO8601 is not used here because it always appends Z and
    would declare a local time to be UTC. }
  Result := FormatDateTime(IsoTimeFormat, ATime, TFormatSettings.Invariant);
end;

function TryTextToTime(const AValue: string; out ATime: TDateTime): Boolean;
var
  Ignored: Integer;
begin
  Result := TryTextToTime(AValue, ATime, Ignored);
end;

function TryTextToTime(const AValue: string; out ATime: TDateTime;
  out AProblem: Integer): Boolean;
begin
  { ioNoTZIsLocal is decision D3 spelled as an option: a string carrying no
    offset is local time. A Z or an explicit offset is honoured and converted,
    which a hand-rolled parser did neither of. }
  try
    Result := TryISO8601ToDate(AValue, ATime, AProblem, [ioNoTZIsLocal]);
  except
    { The RTL parser does not always honour its own Try contract: an offset like
      +99:99 reaches EncodeTime and raises instead of reporting. Letting that
      out would put the guard on every caller, and one caller is an import that
      must survive a bad file. The code is left unknown rather than blamed on
      the time zone, because nothing here proves that is the only path. }
    on EConvertError do
    begin
      AProblem := TimeProblemUnknown;
      Result := False;
    end;
  end;
end;

function TimeProblemToStr(AProblem: Integer): string;
begin
  if (AProblem >= Low(TimeProblemNames)) and (AProblem <= High(TimeProblemNames)) then
    Result := TimeProblemNames[AProblem]
  else
    Result := 'format';
end;

end.
