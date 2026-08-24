unit EventsLog.Schema;

interface

uses
  System.SysUtils, EventsLog.Database;

type
  ESchemaCreateError = class(Exception);

procedure EnsureSchema(ADatabase: TDatabase);

implementation

uses
  FireDAC.Comp.Client;

const
  SqlCreateTable =
    'create table if not exists events (' +
    '  id text primary key,' +
    '  time text not null,' +
    '  text text not null,' +
    '  severity text not null)';
  SqlIndexTime = 'create index if not exists idx_events_time on events(time)';
  SqlIndexSeverity = 'create index if not exists idx_events_severity on events(severity)';

procedure EnsureSchema(ADatabase: TDatabase);
begin
  try
    ADatabase.Connection.ExecSQL(SqlCreateTable);
    ADatabase.Connection.ExecSQL(SqlIndexTime);
    ADatabase.Connection.ExecSQL(SqlIndexSeverity);
  except
    on E: Exception do
      raise ESchemaCreateError.CreateFmt('Cannot prepare the event table in %s.'
        + sLineBreak + '%s: %s', [ADatabase.FileName, E.ClassName, E.Message]);
  end;
end;

end.
