unit TSettingsTests;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  DUnitX.TestFramework, uSettings, uEnums;

type
  [TestFixture]
  TSettingsTestFixture = class
  public
    [Test]
    procedure TestDefaults;
    [Test]
    procedure TestLoadSaveIni;
    [Test]
    procedure TestAssignCopiesAllFields;
    [Test]
    procedure TestAssignSnapshotRollback;
    [Test]
    procedure TestAssignIsDeepCopyOfStrings;
    [Test]
    procedure TestAssignFromNilIsSafe;
  end;

implementation

procedure TSettingsTestFixture.TestDefaults;
var
  S: TSettings;
begin
  S := TSettings.Create;
  try
    Assert.AreEqual(False, S.AutoStart);
    Assert.AreEqual(True, S.ConfirmDelete);
    Assert.AreEqual(1000, S.AutosaveDelay);
    Assert.AreEqual<TNoteColor>(ncYellow, S.DefaultColor);
    Assert.AreEqual(300, S.DefaultWidth);
    Assert.AreEqual(250, S.DefaultHeight);
    Assert.AreEqual(False, S.DefaultAlwaysOnTop);
    Assert.AreEqual(True, S.EnableHotkeys);
    Assert.AreEqual(True, S.BackupEnabled);
    Assert.AreEqual(1, S.BackupIntervalDays);
    Assert.AreEqual(False, S.DarkTheme);
    Assert.AreEqual('Ctrl+Alt+N', S.HotkeyNewNote);
    Assert.AreEqual('Ctrl+Alt+F', S.HotkeySearch);
  finally
    S.Free;
  end;
end;

procedure TSettingsTestFixture.TestLoadSaveIni;
var
  S1, S2: TSettings;
  TempFile: string;
begin
  S1 := TSettings.Create;
  try
    S1.AutosaveDelay := 5000;
    S1.DefaultColor := TNoteColor.ncBlue;
    S1.BackupEnabled := False;
    TempFile := TPath.GetTempPath + 'StickyNotes_Settings_Test.ini';
    try
      S1.SaveToFile(TempFile);
      S2 := TSettings.Create;
      try
        S2.LoadFromFile(TempFile);
        Assert.AreEqual(5000, S2.AutosaveDelay);
        Assert.AreEqual<TNoteColor>(TNoteColor.ncBlue, S2.DefaultColor);
        Assert.AreEqual(False, S2.BackupEnabled);
      finally
        S2.Free;
      end;
    finally
      if TFile.Exists(TempFile) then
        TFile.Delete(TempFile);
    end;
  finally
    S1.Free;
  end;
end;

procedure TSettingsTestFixture.TestAssignCopiesAllFields;
var
  S, Snapshot: TSettings;
begin
  // Phase 4C: TSettings.Assign is the underlying mechanism behind the
  // "Cancel rolls back" behaviour of TSettingsForm. Verify it carries
  // every persisted field, including the strings (which Delphi handles
  // by value but we still want explicit coverage).
  S := TSettings.Create;
  Snapshot := TSettings.Create;
  try
    S.AutoStart := True;
    S.ConfirmDelete := False;
    S.AutosaveDelay := 7500;
    S.DefaultColor := ncPurple;
    S.DefaultWidth := 555;
    S.DefaultHeight := 333;
    S.DefaultAlwaysOnTop := True;
    S.EnableHotkeys := False;
    S.BackupEnabled := False;
    S.BackupIntervalDays := 14;
    S.DarkTheme := True;
    S.HotkeyNewNote := 'Ctrl+Shift+N';
    S.HotkeySearch := 'Ctrl+Shift+S';

    Snapshot.Assign(S);
    Assert.AreEqual(True, Snapshot.AutoStart);
    Assert.AreEqual(False, Snapshot.ConfirmDelete);
    Assert.AreEqual(7500, Snapshot.AutosaveDelay);
    Assert.AreEqual<TNoteColor>(ncPurple, Snapshot.DefaultColor);
    Assert.AreEqual(555, Snapshot.DefaultWidth);
    Assert.AreEqual(333, Snapshot.DefaultHeight);
    Assert.AreEqual(True, Snapshot.DefaultAlwaysOnTop);
    Assert.AreEqual(False, Snapshot.EnableHotkeys);
    Assert.AreEqual(False, Snapshot.BackupEnabled);
    Assert.AreEqual(14, Snapshot.BackupIntervalDays);
    Assert.AreEqual(True, Snapshot.DarkTheme);
    Assert.AreEqual('Ctrl+Shift+N', Snapshot.HotkeyNewNote);
    Assert.AreEqual('Ctrl+Shift+S', Snapshot.HotkeySearch);
  finally
    S.Free;
    Snapshot.Free;
  end;
end;

procedure TSettingsTestFixture.TestAssignSnapshotRollback;
var
  Current, Snapshot: TSettings;
begin
  // Simulates the TSettingsForm Cancel flow at the model level:
  //   1. Snapshot = Current (before dialog)
  //   2. Current is mutated (the dialog edits it)
  //   3. Cancel: Current.Assign(Snapshot) restores the original values.
  Current := TSettings.Create;
  Snapshot := TSettings.Create;
  try
    Current.BackupEnabled := True;
    Current.BackupIntervalDays := 7;
    Current.HotkeyNewNote := 'Original-N';
    Snapshot.Assign(Current);  // Step 1

    // Step 2: mutate Current as if the user typed new values.
    Current.BackupEnabled := False;
    Current.BackupIntervalDays := 30;
    Current.HotkeyNewNote := 'Modified-N';
    Assert.AreEqual(False, Current.BackupEnabled,
      'Sanity: Current now reflects the edited values');

    // Step 3: cancel - rollback via Assign.
    Current.Assign(Snapshot);
    Assert.AreEqual(True, Current.BackupEnabled,
      'Rollback must restore BackupEnabled');
    Assert.AreEqual(7, Current.BackupIntervalDays,
      'Rollback must restore BackupIntervalDays');
    Assert.AreEqual('Original-N', Current.HotkeyNewNote,
      'Rollback must restore HotkeyNewNote');
  finally
    Current.Free;
    Snapshot.Free;
  end;
end;

procedure TSettingsTestFixture.TestAssignIsDeepCopyOfStrings;
var
  A, B: TSettings;
begin
  // Delphi's `string` is reference-counted; an Assign via := into another
  // string field produces a value-copy at the language level. Confirm
  // that mutating A.HotkeyNewNote afterwards does not leak into B.
  A := TSettings.Create;
  B := TSettings.Create;
  try
    A.HotkeyNewNote := 'Before';
    B.Assign(A);
    A.HotkeyNewNote := 'After';
    Assert.AreEqual('Before', B.HotkeyNewNote,
      'Assign must give B its own string value, not share A''s reference');
  finally
    A.Free;
    B.Free;
  end;
end;

procedure TSettingsTestFixture.TestAssignFromNilIsSafe;
var
  S: TSettings;
begin
  // Defensive: TSettingsForm.LoadSettings may pass nil in degenerate
  // scenarios. The existing Assign(Source: TSettings) guards against it.
  S := TSettings.Create;
  try
    S.AutoStart := True; // give it a non-default value
    S.Assign(nil);
    Assert.AreEqual(True, S.AutoStart,
      'Assign(nil) must not corrupt existing values');
  finally
    S.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSettingsTestFixture);

end.