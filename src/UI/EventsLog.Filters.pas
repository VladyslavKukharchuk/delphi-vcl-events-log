unit EventsLog.Filters;

interface

uses
  Vcl.StdCtrls,
  EventsLog.Event, EventsLog.Filter;

type
  TFilters = class
  private
    FEdit: TEdit;
    FCombo: TComboBox;
    procedure FillSeverities;
    function SelectedSeverities: TSeveritySet;
  public
    constructor Create(AEdit: TEdit; ACombo: TComboBox);
    function Filter: TEventFilter;
    procedure SetEnabled(AValue: Boolean);
  end;

implementation

const
  SeverityAllIndex = 0;

resourcestring
  SSeverityAll = 'All';

constructor TFilters.Create(AEdit: TEdit; ACombo: TComboBox);
begin
  inherited Create;
  FEdit := AEdit;
  FCombo := ACombo;
  FillSeverities;
end;

procedure TFilters.FillSeverities;
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

function TFilters.SelectedSeverities: TSeveritySet;
begin
  if FCombo.ItemIndex <= SeverityAllIndex then
    Exit(AllSeverities);
  Result := [TEventSeverity(FCombo.ItemIndex - 1)];
end;

function TFilters.Filter: TEventFilter;
begin
  Result := TEventFilter.Create(FEdit.Text, SelectedSeverities);
end;

procedure TFilters.SetEnabled(AValue: Boolean);
begin
  FEdit.Enabled := AValue;
  FCombo.Enabled := AValue;
end;

end.
