unit EventsLog.FilterPanel;

interface

uses
  Vcl.StdCtrls,
  EventsLog.Event, EventsLog.Filter;

type
  { The search box and the severity list, read together as one filter value.
    Nothing is cached: the two controls are the state, so there is no third copy
    of the filter that could fall behind them (ADR 0012).

    The controls belong to the form. This class drives them and must not free
    them. }
  TFilterPanel = class
  private
    FEdit: TEdit;
    FCombo: TComboBox;
    procedure FillSeverities;
    function SelectedSeverities: TSeveritySet;
  public
    { Fills the severity list and selects the entry standing for all of them. }
    constructor Create(AEdit: TEdit; ACombo: TComboBox);
    { What the user is asking to see, right now. With an empty search box and
      "All" selected this is TEventFilter.Unfiltered, which is what the window
      starts out showing. }
    function Filter: TEventFilter;
    procedure SetEnabled(AValue: Boolean);
  end;

implementation

const
  { The entry in front of the severity names, standing for all of them. }
  SeverityAllIndex = 0;

resourcestring
  SSeverityAll = 'All';

constructor TFilterPanel.Create(AEdit: TEdit; ACombo: TComboBox);
begin
  inherited Create;
  FEdit := AEdit;
  FCombo := ACombo;
  FillSeverities;
end;

{ The names come from the model rather than from the form designer, so adding a
  severity level to the enumeration adds it to this list as well. }
procedure TFilterPanel.FillSeverities;
var
  Severity: TEventSeverity;
begin
  FCombo.Items.BeginUpdate;
  try
    FCombo.Items.Clear;
    FCombo.Items.Add(SSeverityAll);
    for Severity := Low(TEventSeverity) to High(TEventSeverity) do
      FCombo.Items.Add(SeverityToStr(Severity));
  finally
    FCombo.Items.EndUpdate;
  end;
  FCombo.ItemIndex := SeverityAllIndex;
end;

{ The list holds one severity per entry after the "All" one and in the order of
  the enumeration, which is what FillSeverities put there. }
function TFilterPanel.SelectedSeverities: TSeveritySet;
begin
  if FCombo.ItemIndex <= SeverityAllIndex then
    Exit(AllSeverities);
  Result := [TEventSeverity(FCombo.ItemIndex - 1)];
end;

function TFilterPanel.Filter: TEventFilter;
begin
  Result := TEventFilter.Create(FEdit.Text, SelectedSeverities);
end;

procedure TFilterPanel.SetEnabled(AValue: Boolean);
begin
  FEdit.Enabled := AValue;
  FCombo.Enabled := AValue;
end;

end.
