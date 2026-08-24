program EventsLog;

uses
  System.SysUtils,
  Vcl.Forms,
  { Registers FireDAC's wait-cursor provider for the whole program. Nothing
    references it; being linked in is the point. It lives here, in the
    composition root, so that src/Repository stays free of Vcl.* (ADR 0001). }
  FireDAC.VCLUI.Wait,
  Main in 'src\UI\Main.pas' {MainForm},
  EventsLog.Event in 'src\Model\EventsLog.Event.pas',
  EventsLog.Filter in 'src\Model\EventsLog.Filter.pas',
  EventsLog.Database in 'src\Repository\EventsLog.Database.pas',
  EventsLog.EventRepository in 'src\Repository\EventsLog.EventRepository.pas',
  EventsLog.Json in 'src\Repository\EventsLog.Json.pas',
  EventsLog.Generator in 'src\Services\EventsLog.Generator.pas',
  EventsLog.GeneratorSession in 'src\Services\EventsLog.GeneratorSession.pas',
  EventsLog.EventTable in 'src\UI\EventsLog.EventTable.pas',
  EventsLog.FilterPanel in 'src\UI\EventsLog.FilterPanel.pas',
  EventsLog.Actions in 'src\UI\EventsLog.Actions.pas';

{$R *.res}

{ The composition root (ADR 0013). The object graph is built here, once, and
  handed to the window; nothing below this line creates a dependency of its own. }
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
      { Only src/UI may show a dialog, so the reason travels as a string and the
        window is what says it. Repository stays nil, which is how the window
        knows there is nothing to work with. }
      on E: Exception do
        Problem := E.Message;
    end;
    Application.CreateForm(TMainForm, MainForm);
    MainForm.Attach(Repository, Problem);
    Application.Run;
  finally
    { This order is load-bearing, and the first line is the whole reason the
      block exists. An auto-created form is owned by Application and would
      otherwise be destroyed during unit finalisation - after this block - so
      FormDestroy would stop the generator, and that stores an event, through a
      repository that had already gone. Freeing the form here puts its
      destructor back in front of ours; Application.ControlDestroyed clears
      MainForm for us. Then the last reference to the repository goes, and only
      then the database it was reading from. }
    FreeAndNil(MainForm);
    Repository := nil;
    Database.Free;
  end;
end.
