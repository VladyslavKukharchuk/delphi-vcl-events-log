program EventsLogTests;

{$APPTYPE CONSOLE}
{ DUnitX finds fixtures through RTTI, which the linker would otherwise strip. }
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  EventsLog.Event in '..\src\Model\EventsLog.Event.pas',
  EventsLog.Json in '..\src\Repository\EventsLog.Json.pas',
  EventsLog.Json.Tests in 'EventsLog.Json.Tests.pas';

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
    Write('Done. Press Enter to close.');
    Readln;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
