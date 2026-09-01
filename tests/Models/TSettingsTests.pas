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

initialization
  TDUnitX.RegisterTestFixture(TSettingsTestFixture);

end.