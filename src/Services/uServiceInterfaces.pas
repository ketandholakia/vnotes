unit uServiceInterfaces;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Winapi.Windows, Winapi.Messages,
  Vcl.Graphics,
  uNote, uSettings, uEnums, uStorage, uStorageMigrationService, uILogger;

type
  THotkeyID = (hkNewNote, hkSearch);
  THotkeyEvent = procedure of object;

  TBackupProgress = procedure(const AMessage: string; AProgress: Integer) of object;
  TBackupComplete = procedure(ASuccess: Boolean; const AMessage: string) of object;
  TStorageSwapEvent = procedure(Sender: TObject) of object;

  IAutosaveService = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567891}']
    procedure ScheduleSave(ANote: TNote);
    procedure CancelSave(const ANoteID: Int64);
    procedure Flush;
    function GetOnSave: TProc<TNote>;
    procedure SetOnSave(const Value: TProc<TNote>);
    function GetDelay: Integer;
    procedure SetDelay(const Value: Integer);
    property OnSave: TProc<TNote> read GetOnSave write SetOnSave;
    property Delay: Integer read GetDelay write SetDelay;
  end;

  IBackupService = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567892}']
    function Backup: Boolean;
    procedure Restore(const ABackupFile: string);
    procedure CleanupOldBackups;
    function GetBackupFileName: string;
    function GetOnProgress: TBackupProgress;
    procedure SetOnProgress(const Value: TBackupProgress);
    function GetOnComplete: TBackupComplete;
    procedure SetOnComplete(const Value: TBackupComplete);
    function GetOnBeforeStorageSwap: TStorageSwapEvent;
    procedure SetOnBeforeStorageSwap(const Value: TStorageSwapEvent);
    function GetOnAfterStorageSwap: TStorageSwapEvent;
    procedure SetOnAfterStorageSwap(const Value: TStorageSwapEvent);
    property OnProgress: TBackupProgress read GetOnProgress write SetOnProgress;
    property OnComplete: TBackupComplete read GetOnComplete write SetOnComplete;
    property OnBeforeStorageSwap: TStorageSwapEvent read GetOnBeforeStorageSwap write SetOnBeforeStorageSwap;
    property OnAfterStorageSwap: TStorageSwapEvent read GetOnAfterStorageSwap write SetOnAfterStorageSwap;
  end;

  IHotkeyService = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567893}']
    function RegisterHotkey(AID: THotkeyID; const AHotkeyStr: string; AEvent: THotkeyEvent): Boolean;
    function UnregisterHotkey(AID: THotkeyID): Boolean;
    procedure SetHotkey(AID: THotkeyID; const AHotkeyStr: string; AEvent: THotkeyEvent);
    procedure EnableHotkey(AID: THotkeyID; AEnable: Boolean);
    procedure HandleMessage(var Message: TMessage);
    function GetFailedRegistrations: string;
    procedure ShowHotkeyFailures;
  end;

  IThemeService = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567894}']
    procedure SetDarkTheme(ADark: Boolean);
    function GetNoteColor(ANoteColor: TNoteColor): TColor;
    function GetNoteTextColor(ANoteColor: TNoteColor): TColor;
    function GetBackgroundColor: TColor;
    function GetTextColor: TColor;
    function GetBorderColor: TColor;
    function GetButtonColor: TColor;
    function GetButtonTextColor: TColor;
    function GetHighlightColor: TColor;
    function GetDarkTheme: Boolean;
    property DarkTheme: Boolean read GetDarkTheme;
  end;

  IBackupScheduler = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567895}']
    procedure Start;
    procedure Stop;
    procedure Refresh;
    procedure TickNow;
    function GetIsRunning: Boolean;
    function GetIsBusy: Boolean;
    function GetLastBackupAt: TDateTime;
    function GetIntervalDays: Integer;
    property IsRunning: Boolean read GetIsRunning;
    property IsBusy: Boolean read GetIsBusy;
    property LastBackupAt: TDateTime read GetLastBackupAt;
    property IntervalDays: Integer read GetIntervalDays;
  end;

  IStartupService = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567896}']
    function IsAutoStartEnabled: Boolean;
    procedure SetAutoStart(AEnable: Boolean);
    function GetStartupFolder: string;
  end;

  IStorageMigrationService = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567897}']
    function MigrateJsonToSQLite(const AAppDataPath: string): TMigrationResult;
  end;

  IStorageMigrationOrchestrator = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567898}']
    function OrchestrateStorage(const AAppDataPath: string; ASettings: TSettings; const ASettingsPath: string = ''): INoteStorage;
    function ReconcileInterruptedMigration(const AAppDataPath: string; const ANotesPath: string): Boolean;
    procedure QuarantineDatabase(const AAppDataPath: string);
  end;

  TSyncProgress = procedure(const AMessage: string; AProgress: Integer) of object;
  TSyncComplete = procedure(ASuccess: Boolean; const AMessage: string) of object;

  // Phase 7B: transport abstraction for cloud/file sync. A backend stores opaque
  // named objects (one per note, keyed by guid) and knows nothing about note
  // semantics, so folder / WebDAV / provider-SDK backends are drop-in.
  ISyncBackend = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567899}']
    // Human-readable target, e.g. the folder path or remote URL (for messages).
    function DisplayName: string;
    // All object names currently present remotely.
    function ListNames: TArray<string>;
    // Object content, or '' when absent.
    function Read(const AName: string): string;
    procedure Write(const AName, AContent: string);
    procedure Remove(const AName: string);
  end;

  ISyncService = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567900}']
    function IsConfigured: Boolean;
    function SyncNow: Boolean;
    function GetOnProgress: TSyncProgress;
    procedure SetOnProgress(const Value: TSyncProgress);
    function GetOnComplete: TSyncComplete;
    procedure SetOnComplete(const Value: TSyncComplete);
    property OnProgress: TSyncProgress read GetOnProgress write SetOnProgress;
    property OnComplete: TSyncComplete read GetOnComplete write SetOnComplete;
  end;

  // Phase 7D: periodic background sync, mirroring IBackupScheduler.
  ISyncScheduler = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567901}']
    procedure Start;
    procedure Stop;
    procedure Refresh;
    procedure TickNow;
    function GetIsRunning: Boolean;
    function GetIsBusy: Boolean;
    function GetLastSyncAt: TDateTime;
    function GetIntervalMinutes: Integer;
    property IsRunning: Boolean read GetIsRunning;
    property IsBusy: Boolean read GetIsBusy;
    property LastSyncAt: TDateTime read GetLastSyncAt;
    property IntervalMinutes: Integer read GetIntervalMinutes;
  end;

implementation

end.