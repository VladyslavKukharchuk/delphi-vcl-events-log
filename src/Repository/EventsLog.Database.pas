unit EventsLog.Database;

interface

uses
  System.SysUtils, FireDAC.Comp.Client;

type
  EEventsDatabaseError = class(Exception);

  { Owns the connection to the local SQLite database and makes sure its schema
    exists. Units in this layer take the connection from here; nothing outside
    the layer sees it. }
  TEventsDatabase = class
  private
    FConnection: TFDConnection;
    FFileName: string;
    procedure EnsureDirectory;
    procedure Configure;
    procedure EnsureSchema;
  public
    constructor Create;
    destructor Destroy; override;
    property Connection: TFDConnection read FConnection;
    property FileName: string read FFileName;
  end;

function DatabaseDirectory: string;
function DatabaseFileName: string;

implementation

uses
  System.IOUtils,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.Stan.Def,
  FireDAC.Stan.Async, FireDAC.UI.Intf, FireDAC.ConsoleUI.Wait,
  FireDAC.Phys.Intf, FireDAC.Phys, FireDAC.Phys.SQLite, FireDAC.Phys.SQLiteDef,
  FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.DatS, FireDAC.DApt.Intf, FireDAC.DApt;

const
  DatabaseFolderName = 'EventsLog';
  DatabaseName = 'events.db';

  SqlCreateTable =
    'create table if not exists events (' +
    '  id text primary key,' +
    '  time text not null,' +
    '  text text not null,' +
    '  severity text not null)';
  SqlIndexTime = 'create index if not exists idx_events_time on events(time)';
  SqlIndexSeverity = 'create index if not exists idx_events_severity on events(severity)';

function DatabaseDirectory: string;
begin
  Result := TPath.Combine(TPath.GetCachePath, DatabaseFolderName);
end;

function DatabaseFileName: string;
begin
  Result := TPath.Combine(DatabaseDirectory, DatabaseName);
end;

{ TEventsDatabase }

constructor TEventsDatabase.Create;
begin
  inherited Create;
  FFileName := DatabaseFileName;
  EnsureDirectory;
  FConnection := TFDConnection.Create(nil);
  try
    Configure;
    FConnection.Open;
    EnsureSchema;
  except
    on E: Exception do
    begin
      FreeAndNil(FConnection);
      raise EEventsDatabaseError.CreateFmt('Cannot open the event database %s.'
        + sLineBreak + '%s: %s', [FFileName, E.ClassName, E.Message]);
    end;
  end;
end;

destructor TEventsDatabase.Destroy;
begin
  FConnection.Free;
  inherited;
end;

procedure TEventsDatabase.EnsureDirectory;
begin
  if not ForceDirectories(DatabaseDirectory) then
    raise EEventsDatabaseError.CreateFmt('Cannot create the data directory %s.',
      [DatabaseDirectory]);
end;

procedure TEventsDatabase.Configure;
begin
  FConnection.DriverName := 'SQLite';
  FConnection.LoginPrompt := False;
  FConnection.Params.Values['Database'] := FFileName;
  { The driver defaults to an exclusive lock on the file, which would stop a
    second connection from opening it at all. Normal locking plus a WAL journal
    keeps a writer and a reader from blocking each other. }
  FConnection.Params.Values['LockingMode'] := 'Normal';
  FConnection.Params.Values['JournalMode'] := 'WAL';
  FConnection.Params.Values['Synchronous'] := 'Normal';
end;

procedure TEventsDatabase.EnsureSchema;
begin
  { ExecSQL runs one statement per call. }
  FConnection.ExecSQL(SqlCreateTable);
  FConnection.ExecSQL(SqlIndexTime);
  FConnection.ExecSQL(SqlIndexSeverity);
end;

end.
