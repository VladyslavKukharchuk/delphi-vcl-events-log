unit EventsLog.EventRepository;

interface

uses
  System.SysUtils, EventsLog.Event, EventsLog.Filter, EventsLog.Database;

type
  EEventRepositoryError = class(Exception);
  IEventRepository = interface
    ['{F33D6671-3303-4230-AF2C-5427DE0BF82D}']
    procedure Insert(const AEvent: TLogEvent);
    procedure InsertMany(const AEvents: TArray<TLogEvent>);
    procedure DeleteAll;
    function Count(const AFilter: TEventFilter): Int64;
    function Page(const AFilter: TEventFilter;
      AOffset, ALimit: Integer): TArray<TLogEvent>;
  end;

  TEventRepository = class(TInterfacedObject, IEventRepository)
  private
    FDatabase: TDatabase;
    procedure Store(const ASql: string; const AEvent: TLogEvent);
  public
    constructor Create(ADatabase: TDatabase);
    procedure Insert(const AEvent: TLogEvent);
    procedure InsertMany(const AEvents: TArray<TLogEvent>);
    procedure DeleteAll;
    function Count(const AFilter: TEventFilter): Int64;
    function Page(const AFilter: TEventFilter;
      AOffset, ALimit: Integer): TArray<TLogEvent>;
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
  { id breaks ties on time, and it is there for correctness rather than for
    order. Each page is its own query, free to sequence equal timestamps
    differently from the last one, so without a unique final key an event
    stored in the same millisecond as its neighbour can show up on two pages
    or on neither. A JSON import is where that actually happens. }
  SqlPageOrder = ' order by time desc, id desc limit :limit offset :offset';

  SUnreadableColumn = 'The stored event has an unreadable %s: %s';

{ Escapes what SQL LIKE would otherwise read as pattern syntax, so a user
  typing % searches for a per cent sign instead of matching everything. The
  backslash has to be doubled first: doing it after % and _ would escape the
  backslashes those two lines just added. }
function LikePattern(const AText: string): string;
begin
  Result := AText
    .Replace('\', '\\', [rfReplaceAll])
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

constructor TEventRepository.Create(ADatabase: TDatabase);
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

function TEventRepository.Page(const AFilter: TEventFilter;
  AOffset, ALimit: Integer): TArray<TLogEvent>;
var
  Cursor: TFDQuery;
  Events: TList<TLogEvent>;
begin
  Cursor := TFDQuery.Create(nil);
  try
    Cursor.Connection := FDatabase.Connection;
    Cursor.SQL.Text := SqlSelect + WhereClause(AFilter) + SqlPageOrder;
    BindFilter(Cursor, AFilter);
    Cursor.ParamByName('limit').AsInteger := ALimit;
    Cursor.ParamByName('offset').AsInteger := AOffset;
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
