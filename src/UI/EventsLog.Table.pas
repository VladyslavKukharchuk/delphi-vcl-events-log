unit EventsLog.Table;

interface

uses
  Vcl.ComCtrls,
  EventsLog.Event, EventsLog.Filter, EventsLog.EventRepository;

type
  TEventTable = class
  private
    FListView: TListView;
    FVisible: TArray<TLogEvent>;
  public
    constructor Create(AListView: TListView);
    procedure Refresh(const ARepository: IEventRepository;
      const AFilter: TEventFilter);
    procedure ProvideItem(AItem: TListItem);
    procedure Clear;
  end;

implementation

constructor TEventTable.Create(AListView: TListView);
begin
  inherited Create;
  FListView := AListView;
end;

procedure TEventTable.Refresh(const ARepository: IEventRepository;
  const AFilter: TEventFilter);
begin
  FVisible := ARepository.Query(AFilter);
  FListView.Items.Count := Length(FVisible);
  FListView.Invalidate;
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

procedure TEventTable.Clear;
begin
  FVisible := nil;
  FListView.Items.Count := 0;
  FListView.Invalidate;
end;

end.
