unit Main;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.UITypes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, Vcl.ExtCtrls,
  Vcl.StdCtrls,
  EventsLog.EventRepository,
  EventsLog.EventTable, EventsLog.FilterPanel, EventsLog.Actions;

type
  { The window, and the wiring of the three blocks it is made of: the table, the
    filter panel and the actions behind the buttons (ADR 0012). It creates them,
    hands each the controls it drives, and connects them to one another. That is
    why every handler below is one line - the decisions live in the blocks, and
    the only thing left here is who to tell.

    It does not create the repository. That happens in the composition root and
    arrives through Attach, which is also where the window is told that there is
    no database to work with at all (ADR 0013). }
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
    { Held, not owned: a repository is reference counted, and the composition
      root drops the last reference after this form is gone. Nil until Attach,
      and nil for good when there is no database - which is the whole of the
      degraded state (ADR 0013). }
    FRepository: IEventRepository;
    FTable: TEventTable;
    FFilters: TFilterPanel;
    FActions: TEventActions;
    procedure DataChanged(Sender: TObject);
    procedure ShowGeneratingState;
    procedure EnterDegradedMode(const AMessage: string);
  public
    { Called by the composition root after the form exists and before the
      application runs. ARepository is nil when the database could not be
      opened, and AProblem then says why. }
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

{ Only the controls and the blocks that drive them. There is nothing to show
  yet, because nothing to show it from has arrived (see Attach). }
procedure TMainForm.FormCreate(Sender: TObject);
begin
  FTable := TEventTable.Create(ListViewEvents, StatusBar);
  FFilters := TFilterPanel.Create(EditSearch, ComboSeverity);
end;

procedure TMainForm.Attach(const ARepository: IEventRepository;
  const AProblem: string);
begin
  if ARepository = nil then
  begin
    { The composition root raised with the path in the message. Turning that
      into something the user reads is this form's job, and only this form's. }
    EnterDegradedMode(AProblem);
    Exit;
  end;
  FRepository := ARepository;
  FActions := TEventActions.Create(FRepository, OpenDialogJson);
  FActions.OnDataChanged := DataChanged;
  DataChanged(Self);
end;

procedure TMainForm.EnterDegradedMode(const AMessage: string);
begin
  { Nothing can be stored, so there is nothing to import or generate; nothing
    can be queried, so there is nothing to search or filter either. }
  ButtonImport.Enabled := False;
  ButtonClear.Enabled := False;
  ButtonGenerate.Enabled := False;
  FFilters.SetEnabled(False);
  FTable.ShowUnavailable(SDatabaseUnavailable);
  MessageDlg(AMessage, mtError, [mbOK], 0);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  { The actions go first, because freeing them stops the generator, and a
    running generator still has events to hand over which are stored on this
    thread (ADR 0011). The blocks hold controls they do not own, so freeing them
    leaves the window intact. The repository is not freed here at all: the
    composition root drops the last reference to it once this form is gone. }
  FActions.Free;
  FFilters.Free;
  FTable.Free;
end;

{ The one path that puts the stored history back on the screen. Everything that
  changes the history ends up here: an import, a clear, an arriving generated
  event, or the user changing what they want to see. }
procedure TMainForm.DataChanged(Sender: TObject);
begin
  if FRepository = nil then
    Exit;
  FTable.Refresh(FRepository, FFilters.Filter);
  { Clearing an empty history is a question with one answer, so the button is
    not offered. This is the only place that decides, because it is the only
    place that has just counted. }
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

{ The caption and the timer are read off the session rather than toggled beside
  it, so neither can end up disagreeing with what the generator is doing. }
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
  { The timer is turned off here, before the dialog rather than after it: a
    modal dialog raised while the timer still ran would be reached a second time
    from behind itself. }
  ShowGeneratingState;
  MessageDlg(Failure, mtError, [mbOK], 0);
end;

end.
