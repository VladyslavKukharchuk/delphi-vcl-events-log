unit EventsLog.FilterBar;

interface

uses
  Vcl.StdCtrls,
  EventsLog.Event, EventsLog.Filter;

type
  TFilterBar = class
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

constructor TFilterBar.Create(AEdit: TEdit; ACombo: TComboBox);
begin
  inherited Create;
  FEdit := AEdit;
  FCombo := ACombo;
  FillSeverities;
end;

procedure TFilterBar.FillSeverities;
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

function TFilterBar.SelectedSeverities: TSeveritySet;
begin
  if FCombo.ItemIndex <= SeverityAllIndex then
    Exit(AllSeverities);
  Result := [TEventSeverity(FCombo.ItemIndex - 1)];
end;

function TFilterBar.Filter: TEventFilter;
begin
  Result := TEventFilter.Create(FEdit.Text, SelectedSeverities);
end;

procedure TFilterBar.SetEnabled(AValue: Boolean);
begin
  FEdit.Enabled := AValue;
  FCombo.Enabled := AValue;
end;

end.
