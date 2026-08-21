program EventsLog;

uses
  Vcl.Forms,
  Main in 'src\UI\Main.pas' {MainForm},
  EventsLog.Event in 'src\Model\EventsLog.Event.pas',
  EventsLog.Database in 'src\Repository\EventsLog.Database.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
