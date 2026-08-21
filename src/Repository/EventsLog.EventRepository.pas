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
    procedure Store(const ASql: string; const AEvent: TLogEvent);
  public
    constructor Create(ADatabase: TEventsDatabase);
    { One statement in its own implicit transaction. At one event a second the
      batching InsertMany needs would only buy a window in which events are
      lost (ADR 0007). }
    procedure Insert(const AEvent: TLogEvent);
    { Import appends. The inserts share one explicit transaction, because a file
      can hold thousands of rows (ADR 0009). }
    procedure InsertMany(const AEvents: TArray<TLogEvent>);
    { The only path in the application that removes events, and it removes all
      of them. There is no per-event delete because nothing asks for one. }
    procedure DeleteAll;
    function Query(const AFilter: TEventFilter;
      ALimit: Integer = DefaultQueryLimit): TArray<TLogEvent>;
    function Count: Int64; overload;
    { How many events the filter matches. The window needs it to tell a filter
      that hides events from a query that was capped by its limit. }
    function Count(const AFilter: TEventFilter): Int64; overload;
  end;

implementation

uses
  System.Variants, System.Generics.Collections,
  FireDAC.Comp.Client, FireDAC.Stan.Param;

const
  SqlInsert = 'insert into events (id, time, text, severity) ' +
    'values (:id, :time, :text, :severity)';
  SqlDeleteAll = 'delete from events';
  SqlSelect = 'select id, time, text, severity from events';
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

{ SQL has no list parameter, so the severity list reaches the query as a macro:
  &severities is raw text substitution, safe only because the values come from
  SeverityNames, a compile-time constant, and never from user input. }
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
    Conditions := Conditions + ['severity in (&severities)'];
  if Length(Conditions) = 0 then
    Exit('');
  Result := ' where ' + string.Join(' and ', Conditions);
end;

{ Fills in what WhereClause left open, branching on the same two conditions the
  clause itself branched on: the pattern as a parameter, the severity list as a
  macro. Asking for either one the clause did not emit would raise. }
procedure BindFilter(ACursor: TFDQuery; const AFilter: TEventFilter);
begin
  if AFilter.SearchText <> '' then
    ACursor.ParamByName('pattern').AsString := LikePattern(AFilter.SearchText);
  if AFilter.Severities <> AllSeverities then
    ACursor.MacroByName('severities').AsRaw := SeverityList(AFilter.Severities);
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

procedure TEventRepository.Store(const ASql: string;
  const AEvent: TLogEvent);
begin
  FDatabase.Connection.ExecSQL(ASql, [GuidToText(AEvent.Id),
    TimeToText(AEvent.Time), AEvent.Text, SeverityToStr(AEvent.Severity)]);
end;

procedure TEventRepository.Insert(const AEvent: TLogEvent);
begin
  Store(SqlInsert, AEvent);
end;

procedure TEventRepository.InsertMany(const AEvents: TArray<TLogEvent>);
var
  Event: TLogEvent;
begin
  FDatabase.Connection.StartTransaction;
  try
    for Event in AEvents do
      Store(SqlInsert, Event);
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
    BindFilter(Cursor, AFilter);
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

procedure TEventRepository.DeleteAll;
begin
  FDatabase.Connection.ExecSQL(SqlDeleteAll);
end;

function TEventRepository.Count: Int64;
begin
  Result := FDatabase.Connection.ExecSQLScalar(SqlCount);
end;

function TEventRepository.Count(const AFilter: TEventFilter): Int64;
var
  Cursor: TFDQuery;
begin
  Cursor := TFDQuery.Create(nil);
  try
    Cursor.Connection := FDatabase.Connection;
    Cursor.SQL.Text := SqlCount + WhereClause(AFilter);
    BindFilter(Cursor, AFilter);
    Cursor.Open;
    Result := Cursor.Fields[0].AsLargeInt;
  finally
    Cursor.Free;
  end;
end;

end.
