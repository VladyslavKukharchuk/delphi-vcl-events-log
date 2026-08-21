program EventsLog;

uses
  Vcl.Forms,
  { Registers FireDAC's wait-cursor provider for the whole program. Nothing
    references it; being linked in is the point. It lives here, in the
    composition root, so that src/Repository stays free of Vcl.* (ADR 0001). }
  FireDAC.VCLUI.Wait,
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
