unit Main;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.UITypes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, Vcl.ExtCtrls,
  Vcl.StdCtrls,
  EventsLog.EventRepository,
  EventsLog.Table, EventsLog.FilterBar, EventsLog.Actions;

type
  TMainForm = class(TForm)
    PanelTop: TPanel;
    ButtonImport: TButton;
    ButtonClear: TButton;
    ButtonGenerate: TButton;
    LabelSearch: TLabel;
    EditSearch: TEdit;
    LabelSeverity: TLabel;
    ComboSeverity: TComboBox;
    StatusBar: TStatusBar;
    ListViewEvents: TListView;
    OpenDialogJson: TOpenDialog;
    TimerRefresh: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ListViewEventsData(Sender: TObject; Item: TListItem);
    procedure ButtonImportClick(Sender: TObject);
    procedure ButtonClearClick(Sender: TObject);
    procedure FilterChange(Sender: TObject);
    procedure ButtonGenerateClick(Sender: TObject);
    procedure TimerRefreshTimer(Sender: TObject);
  private
    FRepository: IEventRepository;
    FTable: TEventTable;
    FFilterBar: TFilterBar;
    FActions: TEventActions;
    procedure DataChanged(Sender: TObject);
    procedure ShowGeneratingState;
    procedure EnterDegradedMode(const AMessage: string);
  public
    procedure Attach(const ARepository: IEventRepository;
      const AProblem: string);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

resourcestring
  SDatabaseUnavailable = 'The event database is not available.';
  SStartGenerating = 'Start generating';
  SStopGenerating = 'Stop generating';

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FTable := TEventTable.Create(ListViewEvents, StatusBar);
  FFilterBar := TFilterBar.Create(EditSearch, ComboSeverity);
end;

procedure TMainForm.Attach(const ARepository: IEventRepository;
  const AProblem: string);
begin
  if ARepository = nil then
  begin
    EnterDegradedMode(AProblem);
    Exit;
  end;
  FRepository := ARepository;
  FActions := TEventActions.Create(FRepository, OpenDialogJson);
  FActions.OnDataChanged := DataChanged;
  DataChanged(Self);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FActions.Free;
  FFilterBar.Free;
  FTable.Free;
end;

procedure TMainForm.DataChanged(Sender: TObject);
begin
  if FRepository = nil then
    Exit;
  FTable.Refresh(FRepository, FFilterBar.Filter);
  ButtonClear.Enabled := FTable.StoredCount > 0;
  FActions.ViewRefreshed;
end;

procedure TMainForm.FilterChange(Sender: TObject);
begin
  DataChanged(Sender);
end;

procedure TMainForm.ListViewEventsData(Sender: TObject; Item: TListItem);
begin
  FTable.ProvideItem(Item);
end;

procedure TMainForm.ButtonImportClick(Sender: TObject);
begin
  FActions.Import;
end;

procedure TMainForm.ButtonClearClick(Sender: TObject);
begin
  FActions.Clear;
end;

procedure TMainForm.ButtonGenerateClick(Sender: TObject);
begin
  FActions.ToggleGenerating;
  ShowGeneratingState;
end;

procedure TMainForm.ShowGeneratingState;
begin
  TimerRefresh.Enabled := FActions.IsGenerating;
  if FActions.IsGenerating then
    ButtonGenerate.Caption := SStopGenerating
  else
    ButtonGenerate.Caption := SStartGenerating;
end;

procedure TMainForm.TimerRefreshTimer(Sender: TObject);
var
  Failure: string;
begin
  if not FActions.Poll(Failure) then
    Exit;
  ShowGeneratingState;
  MessageDlg(Failure, mtError, [mbOK], 0);
end;

procedure TMainForm.EnterDegradedMode(const AMessage: string);
begin
  ButtonImport.Enabled := False;
  ButtonClear.Enabled := False;
  ButtonGenerate.Enabled := False;
  FFilterBar.SetEnabled(False);
  FTable.ShowUnavailable(SDatabaseUnavailable);
  MessageDlg(AMessage, mtError, [mbOK], 0);
end;

end.
