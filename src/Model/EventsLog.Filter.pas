unit EventsLog.Filter;

interface

uses
  EventsLog.Event;

type
  TSeveritySet = set of TEventSeverity;

const
  AllSeverities: TSeveritySet = [esInfo, esWarning, esError];

type
  TEventFilter = record
  private
    FSearchText: string;
    FSeverities: TSeveritySet;
  public
    constructor Create(const ASearchText: string; ASeverities: TSeveritySet);
    class function Unfiltered: TEventFilter; static;
    function IsUnfiltered: Boolean;
    property SearchText: string read FSearchText;
    property Severities: TSeveritySet read FSeverities;
  end;

implementation

uses
  System.SysUtils;

{ TEventFilter }

constructor TEventFilter.Create(const ASearchText: string;
  ASeverities: TSeveritySet);
begin
  FSearchText := Trim(ASearchText);
  FSeverities := ASeverities;
end;

class function TEventFilter.Unfiltered: TEventFilter;
begin
  Result := TEventFilter.Create('', AllSeverities);
end;

function TEventFilter.IsUnfiltered: Boolean;
begin
  Result := (FSearchText = '') and (FSeverities = AllSeverities);
end;

end.
