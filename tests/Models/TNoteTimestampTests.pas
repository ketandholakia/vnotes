unit TNoteTimestampTests;

// Regression guard for docs/CODE_REVIEW_2026-09-17.md C1.
//
// Before 2026-09-17 every writer emitted an offset-less local wall-clock
// string and read it back with AReturnUTC = True. The switch to
// System.DateUtils paired an offset-bearing writer with a reader that assumes
// an offset-less string is UTC, which shifted every legacy timestamp by the
// local UTC offset (+05:30 here) and made the shift permanent on the next
// save.
//
// These tests are pure logic - no filesystem, no APPDATA - so they are safe
// to run even while the real application is running.

interface

uses
  System.SysUtils, System.DateUtils,
  DUnitX.TestFramework,
  uIso8601;

type
  [TestFixture]
  TNoteTimestampTestFixture = class
  private
    function Fmt(const AValue: TDateTime): string;
  public
    [Test]
    // The headline regression: a legacy offset-less value must keep its
    // wall-clock instead of being shifted by the local UTC offset.
    procedure TestLegacyNaiveTimestampIsNotShiftedByLocalUtcOffset;
    [Test]
    procedure TestLegacyNaiveTimestampWithMillisecondsIsNotShifted;
    [Test]
    procedure TestCurrentFormatRoundTripsTheInstant;
    [Test]
    procedure TestCurrentFormatEmitsAnExplicitUtcOffset;
    [Test]
    procedure TestOffsetDetection;
    [Test]
    procedure TestEmptyAndUnparseableValuesUseTheSuppliedDefault;
  end;

implementation

function TNoteTimestampTestFixture.Fmt(const AValue: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', AValue);
end;

procedure TNoteTimestampTestFixture.TestLegacyNaiveTimestampIsNotShiftedByLocalUtcOffset;
var
  Parsed: TDateTime;
begin
  // Written by a pre-2026-09-17 build: local wall-clock, no offset.
  Parsed := StoredISO8601ToDateTime('2026-09-09T09:09:02', 0);
  Assert.AreEqual<string>(
    '2026-09-09 09:09:02.000', Fmt(Parsed),
    'a legacy offset-less timestamp must keep its wall-clock value; ' +
    'shifting it by the local UTC offset is the C1 regression');
end;

procedure TNoteTimestampTestFixture.TestLegacyNaiveTimestampWithMillisecondsIsNotShifted;
var
  Parsed: TDateTime;
begin
  Parsed := StoredISO8601ToDateTime('2026-09-17T14:33:25.400', 0);
  Assert.AreEqual<string>(
    '2026-09-17 14:33:25.400', Fmt(Parsed),
    'offset-less values with milliseconds must also be read as local wall-clock');
end;

procedure TNoteTimestampTestFixture.TestCurrentFormatRoundTripsTheInstant;
var
  Original, Parsed: TDateTime;
begin
  Original := EncodeDate(2026, 9, 17) + EncodeTime(14, 33, 25, 400);
  Parsed := StoredISO8601ToDateTime(DateTimeToStoredISO8601(Original), 0);
  Assert.AreEqual<string>(Fmt(Original), Fmt(Parsed),
    'write-then-read must preserve the instant');
end;

procedure TNoteTimestampTestFixture.TestCurrentFormatEmitsAnExplicitUtcOffset;
begin
  Assert.IsTrue(HasExplicitUtcOffset(DateTimeToStoredISO8601(Now)),
    'the current writer must emit an explicit UTC offset so a future reader ' +
    'cannot mistake the value for UTC');
end;

procedure TNoteTimestampTestFixture.TestOffsetDetection;
begin
  Assert.IsTrue(HasExplicitUtcOffset('2026-09-17T14:33:25.400+05:30'), 'positive offset');
  Assert.IsTrue(HasExplicitUtcOffset('2026-09-17T14:33:25-07:00'), 'negative offset');
  Assert.IsTrue(HasExplicitUtcOffset('2026-09-17T09:03:25.400Z'), 'trailing Z');
  Assert.IsFalse(HasExplicitUtcOffset('2026-09-17T14:33:25'), 'legacy naive value');
  Assert.IsFalse(HasExplicitUtcOffset('2026-09-17T14:33:25.400'), 'legacy naive value with ms');
  Assert.IsFalse(HasExplicitUtcOffset(''), 'empty string');
end;

procedure TNoteTimestampTestFixture.TestEmptyAndUnparseableValuesUseTheSuppliedDefault;
var
  Sentinel: TDateTime;
begin
  Sentinel := EncodeDate(2001, 1, 1);
  Assert.AreEqual<string>('2001-01-01 00:00:00.000',
    Fmt(StoredISO8601ToDateTime('', Sentinel)), 'empty value must use the default');
  Assert.AreEqual<string>('2001-01-01 00:00:00.000',
    Fmt(StoredISO8601ToDateTime('   ', Sentinel)), 'blank value must use the default');
  Assert.AreEqual<string>('2001-01-01 00:00:00.000',
    Fmt(StoredISO8601ToDateTime('not-a-date', Sentinel)), 'unparseable value must use the default');
end;

initialization
  TDUnitX.RegisterTestFixture(TNoteTimestampTestFixture);

end.
