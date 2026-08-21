unit EventsLog.EventRepository;

interface

uses
  System.SysUtils, EventsLog.Event, EventsLog.Filter, EventsLog.Database;

const
  DefaultQueryLimit = 1000;

type
  EEventRepositoryError = class(Exception);

  { The only place that speaks SQL. Rows become TLogEvent values before they
    leave, so no dataset crosses out of this layer. }
  TEventRepository = class
  private
    FDatabase: TEventsDatabase;
    procedure InsertRow(const AEvent: TLogEvent);
  public
    constructor Create(ADatabase: TEventsDatabase);
    { One statement in its own implicit transaction. At one event a second the
      batching ReplaceAll needs would only buy a window in which events are
      lost (ADR 0007). }
    procedure Insert(const AEvent: TLogEvent);
    { Import replaces the stored history. The delete and the inserts share one
      explicit transaction, because a file can hold thousands of rows. }
    procedure ReplaceAll(const AEvents: TArray<TLogEvent>);
    function Query(const AFilter: TEventFilter;
      ALimit: Integer = DefaultQueryLimit): TArray<TLogEvent>;
    function Count: Int64;
  end;

implementation

uses
  System.Variants, System.Generics.Collections,
  FireDAC.Comp.Client, FireDAC.Stan.Param;

const
  SqlInsert = 'insert into events (id, time, text, severity) ' +
    'values (:id, :time, :text, :severity)';
  SqlSelect = 'select id, time, text, severity from events';
  SqlDeleteAll = 'delete from events';
  SqlCount = 'select count(*) from events';

  SUnreadableColumn = 'The stored event has an unreadable %s: %s';

{ Escapes what SQL LIKE would otherwise read as pattern syntax, so a user
  typing % searches for a per cent sign instead of matching everything. }
function LikePattern(const AText: string): string;
begin
  Result := AText
    .Replace('\', '\', [rfReplaceAll])
    .Replace('%', '\%', [rfReplaceAll])
    .Replace('_', '\_', [rfReplaceAll]);
  Result := '%' + Result + '%';
end;

{ The severity list is interpolated rather than parametrised: the values come
  from SeverityNames, a compile-time constant, and never from user input. }
function SeverityList(ASeverities: TSeveritySet): string;
var
  Severity: TEventSeverity;
begin
  Result := '';
  for Severity := Low(TEventSeverity) to High(TEventSeverity) do
    if Severity in ASeverities then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + QuotedStr(SeverityNames[Severity]);
    end;
end;

function WhereClause(const AFilter: TEventFilter): string;
var
  Conditions: TArray<string>;
begin
  Conditions := [];
  if AFilter.SearchText <> '' then
    Conditions := Conditions + ['text like :pattern escape ''\'''];
  if AFilter.Severities <> AllSeverities then
    Conditions := Conditions +
      ['severity in (' + SeverityList(AFilter.Severities) + ')'];
  if Length(Conditions) = 0 then
    Exit('');
  Result := ' where ' + string.Join(' and ', Conditions);
end;

function RowToEvent(ACursor: TFDQuery): TLogEvent;
var
  Id: TGUID;
  EventTime: TDateTime;
  Severity: TEventSeverity;
  Raw: string;
begin
  Raw := ACursor.FieldByName('id').AsString;
  if not TryTextToGuid(Raw, Id) then
    raise EEventRepositoryError.CreateFmt(SUnreadableColumn, ['id', Raw]);

  Raw := ACursor.FieldByName('time').AsString;
  if not TryTextToTime(Raw, EventTime) then
    raise EEventRepositoryError.CreateFmt(SUnreadableColumn, ['time', Raw]);

  Raw := ACursor.FieldByName('severity').AsString;
  if not TryStrToSeverity(Raw, Severity) then
    raise EEventRepositoryError.CreateFmt(SUnreadableColumn, ['severity', Raw]);

  Result := TLogEvent.Create(Id, EventTime,
    ACursor.FieldByName('text').AsString, Severity);
end;

{ TEventRepository }

constructor TEventRepository.Create(ADatabase: TEventsDatabase);
begin
  inherited Create;
  FDatabase := ADatabase;
end;

procedure TEventRepository.InsertRow(const AEvent: TLogEvent);
begin
  FDatabase.Connection.ExecSQL(SqlInsert, [GuidToText(AEvent.Id),
    TimeToText(AEvent.Time), AEvent.Text, SeverityToStr(AEvent.Severity)]);
end;

procedure TEventRepository.Insert(const AEvent: TLogEvent);
begin
  InsertRow(AEvent);
end;

procedure TEventRepository.ReplaceAll(const AEvents: TArray<TLogEvent>);
var
  Event: TLogEvent;
begin
  FDatabase.Connection.StartTransaction;
  try
    FDatabase.Connection.ExecSQL(SqlDeleteAll);
    for Event in AEvents do
      InsertRow(Event);
    FDatabase.Connection.Commit;
  except
    FDatabase.Connection.Rollback;
    raise;
  end;
end;

function TEventRepository.Query(const AFilter: TEventFilter;
  ALimit: Integer): TArray<TLogEvent>;
var
  Cursor: TFDQuery;
  Events: TList<TLogEvent>;
begin
  Cursor := TFDQuery.Create(nil);
  try
    Cursor.Connection := FDatabase.Connection;
    Cursor.SQL.Text := SqlSelect + WhereClause(AFilter) +
      ' order by time desc limit :limit';
    if AFilter.SearchText <> '' then
      Cursor.ParamByName('pattern').AsString := LikePattern(AFilter.SearchText);
    Cursor.ParamByName('limit').AsInteger := ALimit;
    Cursor.Open;
    Events := TList<TLogEvent>.Create;
    try
      while not Cursor.Eof do
      begin
        Events.Add(RowToEvent(Cursor));
        Cursor.Next;
      end;
      Result := Events.ToArray;
    finally
      Events.Free;
    end;
  finally
    Cursor.Free;
  end;
end;

function TEventRepository.Count: Int64;
begin
  Result := FDatabase.Connection.ExecSQLScalar(SqlCount);
end;

end.
