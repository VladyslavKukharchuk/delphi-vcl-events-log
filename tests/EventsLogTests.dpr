program EventsLogTests;

{$APPTYPE CONSOLE}
{ DUnitX finds fixtures through RTTI, which the linker would otherwise strip. }
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  EventsLog.Event in '..\src\Model\EventsLog.Event.pas',
  EventsLog.Filter in '..\src\Model\EventsLog.Filter.pas',
  EventsLog.Database in '..\src\Repository\EventsLog.Database.pas',
  EventsLog.EventRepository in '..\src\Repository\EventsLog.EventRepository.pas',
  EventsLog.Json in '..\src\Repository\EventsLog.Json.pas',
  EventsLog.Generator in '..\src\Services\EventsLog.Generator.pas',
  EventsLog.GeneratorSession in '..\src\Services\EventsLog.GeneratorSession.pas',
  EventsLog.Json.Tests in 'EventsLog.Json.Tests.pas',
  EventsLog.GeneratorSession.Tests in 'EventsLog.GeneratorSession.Tests.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;

begin
  try
    Runner := TDUnitX.CreateRunner;
    Runner.AddLogger(TDUnitXConsoleLogger.Create(True));
    Results := Runner.Execute;
    if not Results.AllPassed then
      ExitCode := 1;
    { Any argument means the run is not interactive, so do not block on Enter.
      make test passes one; a double click from Explorer does not. }
    if ParamCount = 0 then
    begin
      Write('Done. Press Enter to close.');
      Readln;
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
