unit EventsLog.EventTable;

interface

uses
  Vcl.ComCtrls,
  EventsLog.Event, EventsLog.Filter, EventsLog.EventRepository;

type
  { The events table and the line under it. It owns the result of the current
    query, because the list view is virtual and reads that array by index
    (ADR 0008), and it owns the sentence that says how much of the history the
    query actually returned.

    The controls belong to the form, which got them from its .dfm. This class
    drives them and must not free them (ADR 0012). }
  TEventTable = class
  private
    FListView: TListView;
    FStatusBar: TStatusBar;
    { The result of the current query, and the only copy of what the user sees. }
    FVisible: TArray<TLogEvent>;
    FStored: Int64;
    function Summary(const AFilter: TEventFilter; AMatching: Int64): string;
  public
    constructor Create(AListView: TListView; AStatusBar: TStatusBar);
    { Runs the query again and repaints. The only place that reads the
      repository on the table's behalf. }
    procedure Refresh(const ARepository: IEventRepository;
      const AFilter: TEventFilter);
    { The list view's OnData, one row at a time. }
    procedure ProvideItem(AItem: TListItem);
    { Nothing can be queried: an empty table, and the reason where the count
      would have been. }
    procedure ShowUnavailable(const AMessage: string);
    { How many events are stored, as of the last Refresh. The form asks, because
      it is the form that owns the button this decides the state of. }
    property StoredCount: Int64 read FStored;
  end;

implementation

uses
  System.SysUtils;

resourcestring
  SShowingSome = 'Showing the %d most recent of %d events';
  SShowingAll = '%d events';
  SMatchingSome = 'Showing the %d most recent of %d matching events, %d stored';
  SMatchingAll = '%d of %d events match the filter';

constructor TEventTable.Create(AListView: TListView; AStatusBar: TStatusBar);
begin
  inherited Create;
  FListView := AListView;
  FStatusBar := AStatusBar;
end;

{ The query is capped, so the window has to say when it is showing less than
  what it could. Silence would read as "this is everything", and under a filter
  so would a bare count: zero matches and an empty database look the same. }
function TEventTable.Summary(const AFilter: TEventFilter;
  AMatching: Int64): string;
begin
  if AFilter.IsUnfiltered then
  begin
    if FStored > Length(FVisible) then
      Result := Format(SShowingSome, [Length(FVisible), FStored])
    else
      Result := Format(SShowingAll, [FStored]);
  end
  else if AMatching > Length(FVisible) then
    Result := Format(SMatchingSome, [Length(FVisible), AMatching, FStored])
  else
    Result := Format(SMatchingAll, [AMatching, FStored]);
end;

procedure TEventTable.Refresh(const ARepository: IEventRepository;
  const AFilter: TEventFilter);
var
  Matching: Int64;
begin
  FVisible := ARepository.Query(AFilter);
  FListView.Items.Count := Length(FVisible);
  FListView.Invalidate;

  FStored := ARepository.Count;
  { Counting twice would be counting the same rows twice when nothing is
    filtered out. }
  if AFilter.IsUnfiltered then
    Matching := FStored
  else
    Matching := ARepository.Count(AFilter);

  FStatusBar.SimpleText := Summary(AFilter, Matching);
end;

procedure TEventTable.ProvideItem(AItem: TListItem);
var
  Event: TLogEvent;
begin
  if (AItem.Index < 0) or (AItem.Index > High(FVisible)) then
    Exit;
  Event := FVisible[AItem.Index];
  AItem.Caption := GuidToText(Event.Id);
  AItem.SubItems.Add(TimeToText(Event.Time));
  AItem.SubItems.Add(SeverityToStr(Event.Severity));
  AItem.SubItems.Add(Event.Text);
end;

procedure TEventTable.ShowUnavailable(const AMessage: string);
begin
  FVisible := nil;
  FStored := 0;
  FListView.Items.Count := 0;
  FListView.Invalidate;
  FStatusBar.SimpleText := AMessage;
end;

end.
