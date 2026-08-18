program EventsLog;

uses
  Vcl.Forms,
  DelphiVCLEventsLog in '..\Embarcadero\Studio\Projects\DelphiVCLEventsLog.pas' {MainForm};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
