unit TMonitorUtilsTests;

interface

uses
  System.SysUtils, System.Types,
  DUnitX.TestFramework,
  uMonitorUtils;

type
  [TestFixture]
  TMonitorUtilsTestFixture = class
  private
    // Deterministic virtual desktop for tests: two monitors.
    //   Monitor 1: 1920x1080 with taskbar, work area 0,0..1920,1040
    //   Monitor 2: to the right at x=1920, 1920x1080, full work area
    function SingleWorkArea: TRect;
    function DualWorkAreas: TArray<TRect>;
  public
    [Test]
    procedure TestRectInsideWorkAreaIsVisible;
    [Test]
    procedure TestRectTouchingEdgeIsVisible;
    [Test]
    procedure TestRectEntirelyLeftOfDesktopIsNotVisible;
    [Test]
    procedure TestRectEntirelyRightOfDesktopIsNotVisible;
    [Test]
    procedure TestRectEntirelyBelowDesktopIsNotVisible;
    [Test]
    procedure TestVisibleRectIsReturnedUnchanged;
    [Test]
    procedure TestInvisibleRectIsClampedIntoWorkArea;
    [Test]
    procedure TestClampedRectPreservesSize;
    [Test]
    procedure TestClampedRectOverlapsWorkArea;
    [Test]
    procedure TestEmptyWorkAreasLeavesRectAlone;
    [Test]
    procedure TestPartiallyVisibleRectIsNotMoved;
  end;

implementation

function TMonitorUtilsTestFixture.SingleWorkArea: TRect;
begin
  Result := Rect(0, 0, 1920, 1040);
end;

function TMonitorUtilsTestFixture.DualWorkAreas: TArray<TRect>;
begin
  SetLength(Result, 2);
  Result[0] := Rect(0, 0, 1920, 1040);        // primary
  Result[1] := Rect(1920, 0, 3840, 1080);     // secondary, right of primary
end;

procedure TMonitorUtilsTestFixture.TestRectInsideWorkAreaIsVisible;
var
  R: TRect;
begin
  R := Rect(100, 100, 400, 350);
  Assert.IsTrue(TMonitorUtils.IsRectOnAnyWorkArea(R, [SingleWorkArea]));
end;

procedure TMonitorUtilsTestFixture.TestRectTouchingEdgeIsVisible;
var
  R: TRect;
begin
  // Touching an edge does not count as overlap per the implementation,
  // but a rect just inside the right edge must be visible.
  R := Rect(1918, 100, 1920, 350);
  Assert.IsTrue(TMonitorUtils.IsRectOnAnyWorkArea(R, [SingleWorkArea]));
end;

procedure TMonitorUtilsTestFixture.TestRectEntirelyLeftOfDesktopIsNotVisible;
var
  R: TRect;
begin
  // Note parked at x = -1000 (fully off the left of every monitor).
  R := Rect(-1300, 100, -1000, 350);
  Assert.IsFalse(TMonitorUtils.IsRectOnAnyWorkArea(R, DualWorkAreas));
end;

procedure TMonitorUtilsTestFixture.TestRectEntirelyRightOfDesktopIsNotVisible;
var
  R: TRect;
begin
  R := Rect(5000, 100, 5300, 350);
  Assert.IsFalse(TMonitorUtils.IsRectOnAnyWorkArea(R, DualWorkAreas));
end;

procedure TMonitorUtilsTestFixture.TestRectEntirelyBelowDesktopIsNotVisible;
var
  R: TRect;
begin
  R := Rect(100, 2000, 400, 2250);
  Assert.IsFalse(TMonitorUtils.IsRectOnAnyWorkArea(R, DualWorkAreas));
end;

procedure TMonitorUtilsTestFixture.TestVisibleRectIsReturnedUnchanged;
var
  R, Out_: TRect;
begin
  R := Rect(100, 100, 400, 350);
  Out_ := TMonitorUtils.EnsureRectVisible(R, DualWorkAreas);
  Assert.AreEqual(R.Left, Out_.Left);
  Assert.AreEqual(R.Top, Out_.Top);
  Assert.AreEqual(R.Right, Out_.Right);
  Assert.AreEqual(R.Bottom, Out_.Bottom);
end;

procedure TMonitorUtilsTestFixture.TestInvisibleRectIsClampedIntoWorkArea;
var
  R, Out_: TRect;
begin
  R := Rect(-1300, 100, -1000, 350);
  Out_ := TMonitorUtils.EnsureRectVisible(R, DualWorkAreas);
  Assert.IsTrue(TMonitorUtils.IsRectOnAnyWorkArea(Out_, DualWorkAreas),
    'Clamped rect must overlap at least one work area');
end;

procedure TMonitorUtilsTestFixture.TestClampedRectPreservesSize;
var
  R, Out_: TRect;
begin
  R := Rect(-1300, 100, -1000, 350);   // 300 x 250
  Out_ := TMonitorUtils.EnsureRectVisible(R, DualWorkAreas);
  Assert.AreEqual(R.Width, Out_.Width, 'Width must be preserved');
  Assert.AreEqual(R.Height, Out_.Height, 'Height must be preserved');
end;

procedure TMonitorUtilsTestFixture.TestClampedRectOverlapsWorkArea;
var
  R, Out_: TRect;
begin
  // Off-desktop to the right, closest to the secondary monitor.
  R := Rect(5000, 100, 5300, 350);
  Out_ := TMonitorUtils.EnsureRectVisible(R, DualWorkAreas);
  // The clamped rect must sit within the secondary work area bounds.
  Assert.IsTrue(Out_.Left >= 1920, 'Should land on the secondary monitor');
  Assert.IsTrue(Out_.Right <= 3840);
end;

procedure TMonitorUtilsTestFixture.TestEmptyWorkAreasLeavesRectAlone;
var
  R, Out_: TRect;
begin
  R := Rect(-1300, 100, -1000, 350);
  Out_ := TMonitorUtils.EnsureRectVisible(R, []);
  Assert.AreEqual(R.Left, Out_.Left);
  Assert.AreEqual(R.Top, Out_.Top);
end;

procedure TMonitorUtilsTestFixture.TestPartiallyVisibleRectIsNotMoved;
var
  R, Out_: TRect;
begin
  // Half on the primary monitor, half off the left edge: still visible,
  // so the clamp must not touch it ("avoid unnecessarily changing notes").
  R := Rect(-100, 100, 200, 350);
  Out_ := TMonitorUtils.EnsureRectVisible(R, DualWorkAreas);
  Assert.AreEqual(R.Left, Out_.Left);
  Assert.AreEqual(R.Top, Out_.Top);
end;

initialization
  TDUnitX.RegisterTestFixture(TMonitorUtilsTestFixture);

end.