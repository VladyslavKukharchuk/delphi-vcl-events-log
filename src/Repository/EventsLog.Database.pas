unit EventsLog.Database;

interface

uses
  System.SysUtils, FireDAC.Comp.Client;

type
  EDatabaseOpenError = class(Exception);

  TDatabase = class
  private
    FConnection: TFDConnection;
    FFileName: string;
    procedure EnsureDirectory;
    procedure Configure;
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
  FireDAC.Stan.Async, FireDAC.UI.Intf,
  FireDAC.Phys.Intf, FireDAC.Phys, FireDAC.Phys.SQLite, FireDAC.Phys.SQLiteDef,
  FireDAC.Phys.SQLiteWrapper.Stat,
  { This unit issues no query of its own, but FireDAC links dataset support only
    where a DApt unit is used somewhere in the project. Dropping the three below
    leaves every TFDQuery failing at run time (ADR 0016). }
  FireDAC.DatS, FireDAC.DApt.Intf, FireDAC.DApt;

const
  DatabaseFolderName = 'EventsLog';
  DatabaseName = 'events.db';

function DatabaseDirectory: string;
begin
  Result := TPath.Combine(TPath.GetCachePath, DatabaseFolderName);
end;

function DatabaseFileName: string;
begin
  Result := TPath.Combine(DatabaseDirectory, DatabaseName);
end;

{ TDatabase }

constructor TDatabase.Create;
begin
  inherited Create;
  FFileName := DatabaseFileName;
  EnsureDirectory;
  FConnection := TFDConnection.Create(nil);
  try
    Configure;
    FConnection.Open;
  except
    on E: Exception do
    begin
      FreeAndNil(FConnection);
      raise EDatabaseOpenError.CreateFmt('Cannot open the database %s.'
        + sLineBreak + '%s: %s', [FFileName, E.ClassName, E.Message]);
    end;
  end;
end;

destructor TDatabase.Destroy;
begin
  FConnection.Free;
  inherited;
end;

procedure TDatabase.EnsureDirectory;
begin
  if not ForceDirectories(DatabaseDirectory) then
    raise EDatabaseOpenError.CreateFmt('Cannot create the data directory %s.',
      [DatabaseDirectory]);
end;

procedure TDatabase.Configure;
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

end.
