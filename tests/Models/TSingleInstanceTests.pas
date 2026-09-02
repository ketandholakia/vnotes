unit TSingleInstanceTests;

interface

uses
  System.SysUtils, System.Classes,
  DUnitX.TestFramework,
  uSingleInstance;

type
  [TestFixture]
  TSingleInstanceTestFixture = class
  public
    [Test]
    procedure TestAcquireSucceedsForUniqueName;
    [Test]
    procedure TestSecondAcquireReturnsFalse;
    [Test]
    procedure TestReleaseAllowsReacquire;
    [Test]
    procedure TestIsOwnerReflectsState;
    [Test]
    procedure TestMultipleInstancesWithDifferentNamesAreIndependent;
    [Test]
    procedure TestSignalExistingIsNoOpWhenOwner;
  end;

implementation

function UniqueName(const ASuffix: string): string;
begin
  // Tests share a process; use a per-test unique mutex name so they do
  // not interfere with each other or with a running application.
  Result := 'StickyNotes.Test.' + ASuffix + '.' +
    IntToStr(TThread.GetTickCount);
end;

procedure TSingleInstanceTestFixture.TestAcquireSucceedsForUniqueName;
var
  Inst: TSingleInstance;
begin
  Inst := TSingleInstance.Create(UniqueName('AcquireSucceeds'));
  try
    Assert.IsTrue(Inst.Acquire, 'First Acquire on a unique name must succeed');
    Assert.IsTrue(Inst.IsOwner);
  finally
    Inst.Release;
    Inst.Free;
  end;
end;

procedure TSingleInstanceTestFixture.TestSecondAcquireReturnsFalse;
var
  A, B: TSingleInstance;
  Name: string;
begin
  Name := UniqueName('SecondAcquire');
  A := TSingleInstance.Create(Name);
  B := TSingleInstance.Create(Name);
  try
    Assert.IsTrue(A.Acquire, 'A must become owner');
    Assert.IsFalse(B.Acquire, 'B must NOT become owner while A holds it');
    Assert.IsTrue(A.IsOwner);
    Assert.IsFalse(B.IsOwner);
  finally
    A.Release;
    A.Free;
    B.Free;
  end;
end;

procedure TSingleInstanceTestFixture.TestReleaseAllowsReacquire;
var
  A, B: TSingleInstance;
  Name: string;
begin
  Name := UniqueName('ReleaseAllows');
  A := TSingleInstance.Create(Name);
  B := TSingleInstance.Create(Name);
  try
    Assert.IsTrue(A.Acquire);
    Assert.IsFalse(B.Acquire);
    A.Release;
    Assert.IsFalse(A.IsOwner, 'Release must clear ownership flag');
    Assert.IsTrue(B.Acquire, 'After Release a second instance must succeed');
    Assert.IsTrue(B.IsOwner);
  finally
    A.Free;
    B.Free;
  end;
end;

procedure TSingleInstanceTestFixture.TestIsOwnerReflectsState;
var
  Inst: TSingleInstance;
begin
  Inst := TSingleInstance.Create(UniqueName('IsOwner'));
  try
    Assert.IsFalse(Inst.IsOwner, 'IsOwner must be False before Acquire');
    Inst.Acquire;
    Assert.IsTrue(Inst.IsOwner);
    Inst.Release;
    Assert.IsFalse(Inst.IsOwner, 'IsOwner must be False after Release');
  finally
    Inst.Free;
  end;
end;

procedure TSingleInstanceTestFixture.TestMultipleInstancesWithDifferentNamesAreIndependent;
var
  A, B, C: TSingleInstance;
begin
  A := TSingleInstance.Create(UniqueName('MultiA'));
  B := TSingleInstance.Create(UniqueName('MultiB'));
  C := TSingleInstance.Create(UniqueName('MultiC'));
  try
    Assert.IsTrue(A.Acquire);
    Assert.IsTrue(B.Acquire);
    Assert.IsTrue(C.Acquire);
    Assert.IsTrue(A.IsOwner and B.IsOwner and C.IsOwner);
  finally
    A.Free;
    B.Free;
    C.Free;
  end;
end;

procedure TSingleInstanceTestFixture.TestSignalExistingIsNoOpWhenOwner;
var
  Inst: TSingleInstance;
begin
  // SignalExisting should be a safe no-op when the instance is the owner.
  // No exception, no observable change to state.
  Inst := TSingleInstance.Create(UniqueName('SignalNoOp'));
  try
    Assert.IsTrue(Inst.Acquire);
    Inst.SignalExisting;  // must not raise
    Assert.IsTrue(Inst.IsOwner);
  finally
    Inst.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSingleInstanceTestFixture);

end.