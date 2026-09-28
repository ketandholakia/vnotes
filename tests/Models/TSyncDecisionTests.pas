unit TSyncDecisionTests;

// Phase 7G/WP5: pure decision-function tests (design S2/S3).
//
// ReconcileDecision is the deterministic heart of the rewrite: identical
// inputs must produce identical decisions on every replica, role-swapped
// inputs must mirror (and agree on the copy identity), and the winner
// tie-breaks must follow (Rev, DeviceId, content hash) strictly. These tests
// exercise the function directly - no I/O, no notes, no backend.

interface

uses
  System.SysUtils, System.Hash,
  DUnitX.TestFramework,
  uSyncEngine;

type
  [TestFixture]
  TSyncDecisionTestFixture = class
  private
    function BaseInput: TReconcileInput;
  public
    [Test] procedure TestSameInputsProduceSameDecision;
    [Test] procedure TestRoleSwapMirrorsTheDecision;
    [Test] procedure TestWinnerTiebreaksInOrder;
    [Test] procedure TestAbsenceRowsNeverDelete;
    [Test] procedure TestTombstoneRows;
    [Test] procedure TestJournalPullAndClearRows;
  end;

implementation

const
  G1 = '11111111-2222-3333-4444-555555555555';
  DevHigh = 'zz-device-000000000001';
  DevLow = 'aa-device-000000000002';

function TSyncDecisionTestFixture.BaseInput: TReconcileInput;
begin
  // Both sides live, equal revisions, diverged content, known baseline.
  Result := Default(TReconcileInput);
  Result.Guid := G1;
  Result.LocalPresent := True;
  Result.LocalRev := 5;
  Result.LocalDeviceId := DevLow;
  Result.LocalSignature := 'SIG-LOCAL';
  Result.RemotePresent := True;
  Result.RemoteDeleted := False;
  Result.RemoteRev := 5;
  Result.RemoteDeviceId := DevHigh;
  Result.RemoteSignature := 'SIG-REMOTE';
  Result.BaselineKnown := True;
  Result.BaselineRev := 4;
  Result.JournalPresent := False;
  Result.JournalRev := 0;
end;

procedure TSyncDecisionTestFixture.TestSameInputsProduceSameDecision;
var
  D1, D2: TSyncDecision;
begin
  D1 := ReconcileDecision(BaseInput);
  D2 := ReconcileDecision(BaseInput);
  Assert.AreEqual<TSyncDecisionKind>(D1.Kind, D2.Kind);
  Assert.AreEqual<Int64>(D1.PublishRev, D2.PublishRev);
  Assert.AreEqual<Boolean>(D1.ClearJournal, D2.ClearJournal);
  Assert.AreEqual<string>(D1.CopyGuid, D2.CopyGuid);
  Assert.AreEqual<Boolean>(D1.DefensiveWarning, D2.DefensiveWarning);
end;

procedure TSyncDecisionTestFixture.TestRoleSwapMirrorsTheDecision;
var
  In1, In2: TReconcileInput;
  D1, D2: TSyncDecision;
begin
  // The same pair of versions, seen from each side. The winner must be the
  // same version and the copy identity must be identical from both sides.
  In1 := BaseInput; // remote (DevHigh) wins the equal-rev tie-break
  D1 := ReconcileDecision(In1);

  In2 := BaseInput;
  In2.LocalDeviceId := DevHigh;
  In2.LocalSignature := 'SIG-REMOTE';
  In2.RemoteDeviceId := DevLow;
  In2.RemoteSignature := 'SIG-LOCAL';
  D2 := ReconcileDecision(In2);

  // Side 1: winner is remote -> pull-only, copy of the local loser.
  Assert.AreEqual<TSyncDecisionKind>(sdkConflictPull, D1.Kind);
  Assert.AreEqual<Int64>(0, D1.PublishRev);
  // Side 2: winner is local -> publish at max+1, copy of the remote loser
  // (which is the same version the other side preserved locally).
  Assert.AreEqual<TSyncDecisionKind>(sdkConflictPublish, D2.Kind);
  Assert.AreEqual<Int64>(6, D2.PublishRev);
  Assert.AreEqual<string>(D1.CopyGuid, D2.CopyGuid,
    'both sides must derive the identical copy identity for the same loser');
end;

procedure TSyncDecisionTestFixture.TestWinnerTiebreaksInOrder;
var
  In1: TReconcileInput;
  D: TSyncDecision;
  HashLocal, HashRemote: string;
begin
  // (a) Higher revision wins regardless of device id.
  In1 := BaseInput;
  In1.LocalRev := 6; // local lower device id, but higher rev
  D := ReconcileDecision(In1);
  Assert.AreEqual<TSyncDecisionKind>(sdkConflictPublish, D.Kind);
  Assert.AreEqual<Int64>(7, D.PublishRev);

  // (b) Equal revisions: the higher device id wins.
  In1 := BaseInput;
  In1.LocalDeviceId := DevHigh;
  In1.RemoteDeviceId := DevLow;
  D := ReconcileDecision(In1);
  Assert.AreEqual<TSyncDecisionKind>(sdkConflictPublish, D.Kind);

  // (c) Equal revisions and equal device ids: the higher content hash wins.
  In1 := BaseInput;
  In1.LocalDeviceId := 'same-device-00000000000';
  In1.RemoteDeviceId := 'same-device-00000000000';
  HashLocal := LowerCase(THashSHA2.GetHashString(In1.LocalSignature));
  HashRemote := LowerCase(THashSHA2.GetHashString(In1.RemoteSignature));
  D := ReconcileDecision(In1);
  if HashLocal > HashRemote then
    Assert.AreEqual<TSyncDecisionKind>(sdkConflictPublish, D.Kind)
  else
    Assert.AreEqual<TSyncDecisionKind>(sdkConflictPull, D.Kind);
end;

procedure TSyncDecisionTestFixture.TestAbsenceRowsNeverDelete;
var
  In1: TReconcileInput;
  D: TSyncDecision;
begin
  // (a) Local live, remote absent: push; never a deletion, never a copy.
  In1 := BaseInput;
  In1.RemotePresent := False;
  D := ReconcileDecision(In1);
  Assert.AreEqual<TSyncDecisionKind>(sdkPushLocal, D.Kind);
  Assert.AreEqual<Int64>(5, D.PublishRev);
  Assert.AreEqual<string>('', D.CopyGuid);

  // (b) Both absent, journal present: drop the entry, do nothing else.
  In1 := BaseInput;
  In1.LocalPresent := False;
  In1.RemotePresent := False;
  In1.JournalPresent := True;
  In1.JournalRev := 4;
  D := ReconcileDecision(In1);
  Assert.AreEqual<TSyncDecisionKind>(sdkNothing, D.Kind);
  Assert.AreEqual<Boolean>(True, D.ClearJournal);

  // (c) Both absent, no journal: nothing.
  In1 := BaseInput;
  In1.LocalPresent := False;
  In1.RemotePresent := False;
  D := ReconcileDecision(In1);
  Assert.AreEqual<TSyncDecisionKind>(sdkNothing, D.Kind);
  Assert.AreEqual<Boolean>(False, D.ClearJournal);
end;

procedure TSyncDecisionTestFixture.TestTombstoneRows;
var
  In1: TReconcileInput;
  D: TSyncDecision;
begin
  // (a) Remote tombstone, local absent: nothing (drop a stale journal entry).
  In1 := BaseInput;
  In1.LocalPresent := False;
  In1.RemoteDeleted := True;
  In1.RemoteRev := 6;
  In1.JournalPresent := True;
  In1.JournalRev := 4;
  D := ReconcileDecision(In1);
  Assert.AreEqual<TSyncDecisionKind>(sdkNothing, D.Kind);
  Assert.AreEqual<Boolean>(True, D.ClearJournal);

  // (b) Remote tombstone, local unchanged since the baseline: delete locally.
  In1 := BaseInput;
  In1.LocalRev := 4; // == baseline
  In1.RemoteDeleted := True;
  In1.RemoteRev := 5; // > baseline: the tombstone supersedes the common state
  In1.BaselineRev := 4;
  D := ReconcileDecision(In1);
  Assert.AreEqual<TSyncDecisionKind>(sdkDeleteLocal, D.Kind);

  // (c) Remote tombstone, local changed: edit beats delete at max+1.
  In1 := BaseInput;
  In1.LocalRev := 6;
  In1.RemoteDeleted := True;
  In1.RemoteRev := 5;
  D := ReconcileDecision(In1);
  Assert.AreEqual<TSyncDecisionKind>(sdkPushLocal, D.Kind);
  Assert.AreEqual<Int64>(7, D.PublishRev);

  // (d) Remote tombstone, baseline unknown: edit beats delete.
  In1 := BaseInput;
  In1.BaselineKnown := False;
  In1.RemoteDeleted := True;
  In1.RemoteRev := 5;
  D := ReconcileDecision(In1);
  Assert.AreEqual<TSyncDecisionKind>(sdkPushLocal, D.Kind);
end;

procedure TSyncDecisionTestFixture.TestJournalPullAndClearRows;
var
  In1: TReconcileInput;
  D: TSyncDecision;
begin
  // (a) Local absent + journal + remote unchanged since the baseline:
  // write a tombstone at max(revR, journalRev) + 1 and clear the entry.
  In1 := BaseInput;
  In1.LocalPresent := False;
  In1.RemoteRev := 5;
  In1.BaselineRev := 5;
  In1.JournalPresent := True;
  In1.JournalRev := 4;
  D := ReconcileDecision(In1);
  Assert.AreEqual<TSyncDecisionKind>(sdkWriteTombstone, D.Kind);
  Assert.AreEqual<Int64>(6, D.PublishRev);
  Assert.AreEqual<Boolean>(True, D.ClearJournal);

  // (b) Local absent + journal + remote changed since the baseline:
  // edit beats delete - pull and clear the entry.
  In1 := BaseInput;
  In1.LocalPresent := False;
  In1.RemoteRev := 6;
  In1.BaselineRev := 5;
  In1.JournalPresent := True;
  In1.JournalRev := 4;
  D := ReconcileDecision(In1);
  Assert.AreEqual<TSyncDecisionKind>(sdkPullRemote, D.Kind);
  Assert.AreEqual<Boolean>(True, D.ClearJournal);

  // (c) Local absent + journal + baseline unknown: pull and clear.
  In1 := BaseInput;
  In1.LocalPresent := False;
  In1.RemoteRev := 5;
  In1.BaselineKnown := False;
  In1.JournalPresent := True;
  In1.JournalRev := 4;
  D := ReconcileDecision(In1);
  Assert.AreEqual<TSyncDecisionKind>(sdkPullRemote, D.Kind);
  Assert.AreEqual<Boolean>(True, D.ClearJournal);

  // (d) Local absent, no journal: a new remote note is pulled.
  In1 := BaseInput;
  In1.LocalPresent := False;
  In1.RemoteRev := 3;
  D := ReconcileDecision(In1);
  Assert.AreEqual<TSyncDecisionKind>(sdkPullRemote, D.Kind);
  Assert.AreEqual<Boolean>(False, D.ClearJournal);
end;

initialization
  TDUnitX.RegisterTestFixture(TSyncDecisionTestFixture);

end.
