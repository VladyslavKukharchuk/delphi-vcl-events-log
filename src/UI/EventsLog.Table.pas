unit EventsLog.Table;

interface

uses
  Vcl.ComCtrls,
  EventsLog.Event, EventsLog.Filter, EventsLog.EventRepository;

type
  TEventTable = class
  private
    FListView: TListView;
    FStatusBar: TStatusBar;
    FVisible: TArray<TLogEvent>;
    FStored: Int64;
    function Summary(const AFilter: TEventFilter; AMatching: Int64): string;
  public
    constructor Create(AListView: TListView; AStatusBar: TStatusBar);
    procedure Refresh(const ARepository: IEventRepository;
      const AFilter: TEventFilter);
    procedure ProvideItem(AItem: TListItem);
    procedure ShowUnavailable(const AMessage: string);
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
