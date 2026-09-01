unit uNoteEditorContext;

interface

uses
  System.SysUtils,
  Vcl.Graphics,
  uNote, uEnums, uNoteManager, uAutosaveService, uThemeService, uSettings;

type
  /// <summary>
  /// Narrow application-facing interface for note-editor UI (TNoteForm).
  /// Groups only the operations that a note window genuinely needs,
  /// hiding the full service implementations behind a single injected
  /// dependency.
  /// </summary>
  INoteEditorContext = interface
    ['{9A8B7C6D-5E4F-3A2B-1C0D-E9F8A7B6C5D4}']
    // -- Note lifecycle -----------------------------------------------
    procedure SaveNote(const ANote: TNote);
    function DeleteNote(const ANoteID: Int64): Boolean;
    function CreateNote(const ATitle, AContent: string; AColor: TNoteColor): TNote;

    // -- Autosave ----------------------------------------------------
    procedure ScheduleSave(const ANote: TNote);
    procedure CancelSave(const ANoteID: Int64);

    // -- Theme queries (pure functions) ------------------------------
    function GetNoteColor(ANoteColor: TNoteColor): TColor;
    function GetNoteTextColor(ANoteColor: TNoteColor): TColor;

    // -- Settings queries --------------------------------------------
    function GetConfirmDelete: Boolean;
  end;

  /// <summary>
  /// Concrete implementation that delegates to the services owned by
  /// TNoteApplication.
  /// </summary>
  TNoteEditorContext = class(TInterfacedObject, INoteEditorContext)
  private
    FNoteManager: TNoteManager;
    FAutosaveService: TAutosaveService;
    FThemeService: TThemeService;
    FSettings: TSettings;
  public
    constructor Create(ANoteManager: TNoteManager;
      AAutosaveService: TAutosaveService;
      AThemeService: TThemeService;
      ASettings: TSettings);

    // INoteEditorContext
    procedure SaveNote(const ANote: TNote);
    function DeleteNote(const ANoteID: Int64): Boolean;
    function CreateNote(const ATitle, AContent: string; AColor: TNoteColor): TNote;
    procedure ScheduleSave(const ANote: TNote);
    procedure CancelSave(const ANoteID: Int64);
    function GetNoteColor(ANoteColor: TNoteColor): TColor;
    function GetNoteTextColor(ANoteColor: TNoteColor): TColor;
    function GetConfirmDelete: Boolean;
  end;

implementation

{ TNoteEditorContext }

constructor TNoteEditorContext.Create(ANoteManager: TNoteManager;
  AAutosaveService: TAutosaveService;
  AThemeService: TThemeService;
  ASettings: TSettings);
begin
  inherited Create;
  FNoteManager := ANoteManager;
  FAutosaveService := AAutosaveService;
  FThemeService := AThemeService;
  FSettings := ASettings;
end;

procedure TNoteEditorContext.SaveNote(const ANote: TNote);
begin
  FNoteManager.SaveNote(ANote);
end;

function TNoteEditorContext.DeleteNote(const ANoteID: Int64): Boolean;
begin
  Result := FNoteManager.DeleteNote(ANoteID);
end;

function TNoteEditorContext.CreateNote(const ATitle, AContent: string;
  AColor: TNoteColor): TNote;
begin
  Result := FNoteManager.CreateNote(ATitle, AContent, AColor);
end;

procedure TNoteEditorContext.ScheduleSave(const ANote: TNote);
begin
  FAutosaveService.ScheduleSave(ANote);
end;

procedure TNoteEditorContext.CancelSave(const ANoteID: Int64);
begin
  FAutosaveService.CancelSave(ANoteID);
end;

function TNoteEditorContext.GetNoteColor(ANoteColor: TNoteColor): TColor;
begin
  Result := FThemeService.GetNoteColor(ANoteColor);
end;

function TNoteEditorContext.GetNoteTextColor(ANoteColor: TNoteColor): TColor;
begin
  Result := FThemeService.GetNoteTextColor(ANoteColor);
end;

function TNoteEditorContext.GetConfirmDelete: Boolean;
begin
  Result := FSettings.ConfirmDelete;
end;

end.