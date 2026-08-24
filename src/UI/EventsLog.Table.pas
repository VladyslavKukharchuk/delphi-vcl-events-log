unit EventsLog.Table;

interface

uses
  Vcl.ComCtrls, Vcl.StdCtrls,
  EventsLog.Event, EventsLog.Filter, EventsLog.EventRepository;

type
  TEventTable = class
  private
    FListView: TListView;
    FLabelPage: TLabel;
    FButtonPrevious: TButton;
    FButtonNext: TButton;
    FComboPageSize: TComboBox;
    FRepository: IEventRepository;
    FFilter: TEventFilter;
    FPage: Integer;
    FPageSize: Integer;
    FPageCount: Integer;
    FTotal: Integer;
    FRows: TArray<TLogEvent>;
    procedure FillPageSizes;
    function SelectedPageSize: Integer;
    procedure RecountPages;
    procedure LoadPage;
    procedure ScrollToTop;
    procedure ShowPageState;
  public
    constructor Create(AListView: TListView; ALabelPage: TLabel;
      AButtonPrevious, AButtonNext: TButton; AComboPageSize: TComboBox);
    procedure Refresh(const ARepository: IEventRepository;
      const AFilter: TEventFilter);
    procedure GoPrevious;
    procedure GoNext;
    procedure ChangePageSize;
    procedure ProvideItem(AItem: TListItem);
    procedure Clear;
  end;

implementation

uses
  System.SysUtils, Winapi.CommCtrl;

const
  PageSizes: array[0..3] of Integer = (50, 100, 200, 500);
  DefaultPageSizeIndex = 2;

resourcestring
  SPageOf = 'Page %d of %d';
  SNoEvents = 'No events';

constructor TEventTable.Create(AListView: TListView; ALabelPage: TLabel;
  AButtonPrevious, AButtonNext: TButton; AComboPageSize: TComboBox);
begin
  inherited Create;
  FListView := AListView;
  FLabelPage := ALabelPage;
  FButtonPrevious := AButtonPrevious;
  FButtonNext := AButtonNext;
  FComboPageSize := AComboPageSize;
  FillPageSizes;
  FPageSize := SelectedPageSize;
end;

procedure TEventTable.FillPageSizes;
var
  Index: Integer;
begin
  FComboPageSize.Items.BeginUpdate;
  try
    FComboPageSize.Items.Clear;
    for Index := Low(PageSizes) to High(PageSizes) do
      FComboPageSize.Items.Add(IntToStr(PageSizes[Index]));
  finally
    FComboPageSize.Items.EndUpdate;
  end;
  FComboPageSize.ItemIndex := DefaultPageSizeIndex;
end;

function TEventTable.SelectedPageSize: Integer;
begin
  if (FComboPageSize.ItemIndex < Low(PageSizes)) or
    (FComboPageSize.ItemIndex > High(PageSizes)) then
    Exit(PageSizes[DefaultPageSizeIndex]);
  Result := PageSizes[FComboPageSize.ItemIndex];
end;

procedure TEventTable.Refresh(const ARepository: IEventRepository;
  const AFilter: TEventFilter);
var
  Total: Int64;
  Moved: Boolean;
  WasOnPage: Integer;
begin
  Moved := (AFilter.SearchText <> FFilter.SearchText) or
    (AFilter.Severities <> FFilter.Severities);
  if Moved then
    FPage := 0;
  WasOnPage := FPage;
  FRepository := ARepository;
  FFilter := AFilter;

  Total := ARepository.Count(AFilter);
  if Total > MaxInt then
    Total := MaxInt;
  FTotal := Total;

  RecountPages;
  LoadPage;
  { RecountPages can pull the view back when the last page disappears, and a
    new filter starts over at the first page. Either way the rows are not the
    ones that were on screen, so the offset they were read at means nothing. }
  if Moved or (FPage <> WasOnPage) then
    ScrollToTop;
  ShowPageState;
end;

procedure TEventTable.RecountPages;
begin
  FPageCount := FTotal div FPageSize;
  if FTotal mod FPageSize <> 0 then
    Inc(FPageCount);
  if FPageCount < 1 then
    FPageCount := 1;
  if FPage > FPageCount - 1 then
    FPage := FPageCount - 1;
end;

procedure TEventTable.LoadPage;
begin
  FRows := FRepository.Page(FFilter, FPage * FPageSize, FPageSize);
  FListView.Items.Count := Length(FRows);
  FListView.Invalidate;
end;

{ Only for a move to a different page: a new page otherwise opens at the offset
  the previous one was left at. Reloading the same page must not scroll, or
  every generated event would throw the reader back to the top. Refresh can run
  before the form is shown, hence the handle test; Items[0] is not used because
  in OwnerData mode it can return nil. }
procedure TEventTable.ScrollToTop;
begin
  if (Length(FRows) > 0) and FListView.HandleAllocated then
    ListView_EnsureVisible(FListView.Handle, 0, False);
end;

procedure TEventTable.ShowPageState;
begin
  if FTotal = 0 then
    FLabelPage.Caption := SNoEvents
  else
    FLabelPage.Caption := Format(SPageOf, [FPage + 1, FPageCount]);
  FButtonPrevious.Enabled := FPage > 0;
  FButtonNext.Enabled := FPage < FPageCount - 1;
end;

procedure TEventTable.GoPrevious;
begin
  if FPage = 0 then
    Exit;
  Dec(FPage);
  LoadPage;
  ScrollToTop;
  ShowPageState;
end;

procedure TEventTable.GoNext;
begin
  if FPage >= FPageCount - 1 then
    Exit;
  Inc(FPage);
  LoadPage;
  ScrollToTop;
  ShowPageState;
end;

procedure TEventTable.ChangePageSize;
var
  NewSize, FirstRow: Integer;
begin
  NewSize := SelectedPageSize;
  if NewSize = FPageSize then
    Exit;
  { Land on whichever page now holds the row the user was looking at, so
    changing the size moves the boundaries and not the reading position. }
  FirstRow := FPage * FPageSize;
  FPageSize := NewSize;
  FPage := FirstRow div FPageSize;
  if FRepository = nil then
    Exit;
  RecountPages;
  LoadPage;
  ScrollToTop;
  ShowPageState;
end;

procedure TEventTable.ProvideItem(AItem: TListItem);
var
  Event: TLogEvent;
begin
  if (AItem.Index < 0) or (AItem.Index > High(FRows)) then
    Exit;
  Event := FRows[AItem.Index];
  AItem.Caption := GuidToText(Event.Id);
  AItem.SubItems.Add(TimeToText(Event.Time));
  AItem.SubItems.Add(SeverityToStr(Event.Severity));
  AItem.SubItems.Add(Event.Text);
end;

procedure TEventTable.Clear;
begin
  FRepository := nil;
  FRows := nil;
  FTotal := 0;
  FPage := 0;
  FPageCount := 1;
  FListView.Items.Count := 0;
  FListView.Invalidate;
  ShowPageState;
end;

end.
