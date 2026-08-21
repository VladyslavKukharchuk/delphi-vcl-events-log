program EventsLog;

uses
  Vcl.Forms,
  Main in 'src\UI\Main.pas' {MainForm},
  EventsLog.Event in 'src\Model\EventsLog.Event.pas',
  EventsLog.Filter in 'src\Model\EventsLog.Filter.pas',
  EventsLog.Database in 'src\Repository\EventsLog.Database.pas',
  EventsLog.EventRepository in 'src\Repository\EventsLog.EventRepository.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
