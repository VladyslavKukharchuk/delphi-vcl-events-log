program EventsLog;

uses
  System.SysUtils,
  Vcl.Forms,
  FireDAC.VCLUI.Wait,
  Main in 'src\UI\Main.pas' {MainForm},
  EventsLog.Event in 'src\Model\EventsLog.Event.pas',
  EventsLog.Filter in 'src\Model\EventsLog.Filter.pas',
  EventsLog.Database in 'src\Repository\EventsLog.Database.pas',
  EventsLog.EventRepository in 'src\Repository\EventsLog.EventRepository.pas',
  EventsLog.Json in 'src\Repository\EventsLog.Json.pas',
  EventsLog.Generator in 'src\Services\EventsLog.Generator.pas',
  EventsLog.GeneratorSession in 'src\Services\EventsLog.GeneratorSession.pas',
  EventsLog.Table in 'src\UI\EventsLog.Table.pas',
  EventsLog.FilterBar in 'src\UI\EventsLog.FilterBar.pas',
  EventsLog.Actions in 'src\UI\EventsLog.Actions.pas',
  EventsLog.ProblemsDialog in 'src\UI\EventsLog.ProblemsDialog.pas' {ImportProblemsForm};

{$R *.res}

var
  Database: TEventsDatabase;
  Repository: IEventRepository;
  Problem: string;

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  try
    try
      Database := TEventsDatabase.Create;
      Repository := TEventRepository.Create(Database);
    except
      on E: Exception do
        Problem := E.Message;
    end;
    Application.CreateForm(TMainForm, MainForm);
  MainForm.Attach(Repository, Problem);
    Application.Run;
  finally
    FreeAndNil(MainForm);
    Repository := nil;
    Database.Free;
  end;
end.
