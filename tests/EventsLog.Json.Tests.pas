unit EventsLog.Json.Tests;

interface

uses
  DUnitX.TestFramework;

type
  { The loader is a pure function from a file to events plus a report, so it
    needs no database, no form and no seam to be tested - which is why it is
    the first thing here. The sample files are the fixtures. }
  [TestFixture]
  TJsonImportTests = class
  private
    FSamplesPath: string;
    function Sample(const AFileName: string): string;
  public
    [Setup]
    procedure Setup;

    [Test]
    [TestCase('every record usable', 'sample-events.json,12,0')]
    [TestCase('records broken seven ways', 'sample-events-invalid.json,2,7')]
    procedure ReportsAcceptedAndRejected(const AFileName: string;
      AAccepted, ARejected: Integer);

    [Test]
    [TestCase('not valid JSON', 'sample-events-malformed.json')]
    [TestCase('file does not exist', 'no-such-file.json')]
    procedure UnusableFileRaises(const AFileName: string);

    [Test]
    [TestCase('names the record and the field', 'sample-events-invalid.json|record 2 has no time', '|')]
    procedure FirstProblemIsUseful(const AFileName, AExpected: string);

    [Test]
    procedure IdentifiersAreMintedAndDistinct;

    [Test]
    procedure ZuluTimeIsConvertedToLocal;
  end;

  [TestFixture]
  TTimeTextTests = class
  public
    [Test]
    [TestCase('local, with milliseconds', '2026-08-19T08:14:02.000,True')]
    [TestCase('local, without milliseconds', '2026-08-19T08:14:02,True')]
    [TestCase('zulu', '2026-08-19T13:20:00.000Z,True')]
    [TestCase('explicit offset', '2026-08-19T17:05:41.300+03:00,True')]
    [TestCase('prose', 'not a timestamp,False')]
    [TestCase('month 13', '2026-13-01T00:00:00.000,False')]
    [TestCase('impossible offset', '2026-08-20T10:04:00+99:99,False')]
    [TestCase('empty', ',False')]
    procedure AcceptsOrRejects(const AText: string; AExpected: Boolean);

    [Test]
    procedure RoundTripsWhatItWrote;

    [Test]
    [TestCase('month', '2,month')]
    [TestCase('time zone', '8,time zone')]
    [TestCase('above the range', '99,format')]
    [TestCase('zero', '0,format')]
    procedure NamesTheRejectedField(ACode: Integer; const AExpected: string);
  end;

  [TestFixture]
  TSeverityTests = class
  public
    [Test]
    [TestCase('as written', 'Info,True,0')]
    [TestCase('lower case', 'error,True,2')]
    [TestCase('upper case', 'WARNING,True,1')]
    [TestCase('mixed case', 'wArNiNg,True,1')]
    [TestCase('not a level', 'Critical,False,0')]
    [TestCase('empty', ',False,0')]
    procedure AcceptsAnyCasingOfAKnownLevel(const AText: string;
      AExpected: Boolean; AOrdinal: Integer);
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.DateUtils,
  EventsLog.Event, EventsLog.Json;

{ The test executable lives in tests\Win64\Debug, so the fixtures are found by
  walking up until the directory holding them appears. }
function FindSamplesPath: string;
var
  Directory: string;
  Level: Integer;
begin
  Directory := TPath.GetDirectoryName(ParamStr(0));
  for Level := 0 to 5 do
  begin
    if TFile.Exists(TPath.Combine(Directory, 'sample-events.json')) then
      Exit(Directory);
    Directory := TPath.GetDirectoryName(Directory);
  end;
  raise Exception.CreateFmt('Cannot find sample-events.json above %s',
    [ParamStr(0)]);
end;

{ TJsonImportTests }

procedure TJsonImportTests.Setup;
begin
  FSamplesPath := FindSamplesPath;
end;

function TJsonImportTests.Sample(const AFileName: string): string;
begin
  Result := TPath.Combine(FSamplesPath, AFileName);
end;

procedure TJsonImportTests.ReportsAcceptedAndRejected(const AFileName: string;
  AAccepted, ARejected: Integer);
var
  Events: TArray<TLogEvent>;
  Report: TImportReport;
begin
  Events := LoadEventsFromFile(Sample(AFileName), Report);
  Assert.AreEqual(AAccepted, Report.Accepted, 'accepted');
  Assert.AreEqual(ARejected, Report.Rejected, 'rejected');
  Assert.AreEqual(AAccepted, Length(Events), 'events returned');
end;

procedure TJsonImportTests.UnusableFileRaises(const AFileName: string);
var
  Path: string;
begin
  Path := Sample(AFileName);
  Assert.WillRaise(
    procedure
    var
      Report: TImportReport;
    begin
      LoadEventsFromFile(Path, Report);
    end,
    EEventImportError);
end;

procedure TJsonImportTests.FirstProblemIsUseful(const AFileName,
  AExpected: string);
var
  Report: TImportReport;
begin
  LoadEventsFromFile(Sample(AFileName), Report);
  Assert.AreEqual(AExpected, Report.FirstProblem);
end;

procedure TJsonImportTests.IdentifiersAreMintedAndDistinct;
var
  Events: TArray<TLogEvent>;
  Report: TImportReport;
  Seen: string;
  Event: TLogEvent;
  Text: string;
begin
  Events := LoadEventsFromFile(Sample('sample-events.json'), Report);
  Seen := '';
  for Event in Events do
  begin
    Text := GuidToText(Event.Id);
    Assert.AreNotEqual('00000000-0000-0000-0000-000000000000', Text,
      'a minted identifier must not be all zeroes');
    Assert.IsFalse(Seen.Contains(Text), 'identifiers must be distinct: ' + Text);
    Seen := Seen + Text;
  end;
end;

procedure TJsonImportTests.ZuluTimeIsConvertedToLocal;
var
  Events: TArray<TLogEvent>;
  Report: TImportReport;
  Event: TLogEvent;
  Expected: TDateTime;
  Found: Boolean;
begin
  { Computed rather than hard-coded: the expected value depends on the time zone
    of whichever machine runs the test. }
  Expected := TTimeZone.Local.ToLocalTime(EncodeDateTime(2026, 8, 19, 13, 20, 0, 0));
  Events := LoadEventsFromFile(Sample('sample-events.json'), Report);
  Found := False;
  for Event in Events do
    if Event.Text.StartsWith('Recorded in UTC') then
    begin
      Assert.AreEqual(Expected, Event.Time, 'the Z must be honoured');
      Found := True;
    end;
  Assert.IsTrue(Found, 'the fixture no longer contains the UTC record');
end;

{ TTimeTextTests }

procedure TTimeTextTests.AcceptsOrRejects(const AText: string;
  AExpected: Boolean);
var
  Parsed: TDateTime;
begin
  Assert.AreEqual(AExpected, TryTextToTime(AText, Parsed));
end;

procedure TTimeTextTests.RoundTripsWhatItWrote;
var
  Written: string;
  Parsed: TDateTime;
  Original: TDateTime;
begin
  Original := EncodeDateTime(2026, 8, 21, 7, 43, 12, 160);
  Written := TimeToText(Original);
  Assert.IsTrue(TryTextToTime(Written, Parsed), 'written form must parse back');
  Assert.AreEqual(Original, Parsed, 'the round trip must be exact');
end;

procedure TTimeTextTests.NamesTheRejectedField(ACode: Integer;
  const AExpected: string);
begin
  Assert.AreEqual(AExpected, TimeProblemToStr(ACode));
end;

{ TSeverityTests }

procedure TSeverityTests.AcceptsAnyCasingOfAKnownLevel(const AText: string;
  AExpected: Boolean; AOrdinal: Integer);
var
  Severity: TEventSeverity;
begin
  Assert.AreEqual(AExpected, TryStrToSeverity(AText, Severity), 'accepted');
  if AExpected then
    Assert.AreEqual(AOrdinal, Ord(Severity), 'level');
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonImportTests);
  TDUnitX.RegisterTestFixture(TTimeTextTests);
  TDUnitX.RegisterTestFixture(TSeverityTests);

end.
