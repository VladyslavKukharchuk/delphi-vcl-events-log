program EventsLog;

uses
  System.SysUtils,
  Vcl.Forms,
  FireDAC.VCLUI.Wait,
  Main in 'src\UI\Main.pas' {MainForm},
  EventsLog.Event in 'src\Model\EventsLog.Event.pas',
  EventsLog.Filter in 'src\Model\EventsLog.Filter.pas',
  EventsLog.Database in 'src\Repository\EventsLog.Database.pas',
  EventsLog.Schema in 'src\Repository\EventsLog.Schema.pas',
  EventsLog.EventRepository in 'src\Repository\EventsLog.EventRepository.pas',
  EventsLog.EventFile in 'src\Repository\EventsLog.EventFile.pas',
  EventsLog.Generator in 'src\Services\EventsLog.Generator.pas',
  EventsLog.GeneratorSession in 'src\Services\EventsLog.GeneratorSession.pas',
  EventsLog.Table in 'src\UI\EventsLog.Table.pas',
  EventsLog.FilterBar in 'src\UI\EventsLog.FilterBar.pas',
  EventsLog.Actions in 'src\UI\EventsLog.Actions.pas',
  EventsLog.ImportPreview in 'src\UI\EventsLog.ImportPreview.pas' {ImportPreviewForm};

{$R *.res}

var
  Database: TDatabase;
  Repository: IEventRepository;
  Problem: string;

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  try
    try
      Database := TDatabase.Create;
      EnsureSchema(Database);
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
