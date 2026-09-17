unit uAutosaveService;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, Vcl.ExtCtrls,
  uNote, uILogger, uServiceInterfaces;

type
  TAutosaveService = class(TInterfacedObject, IAutosaveService)
  private
    FTimer: TTimer;
    FDelay: Integer;
    FOnSave: TProc<TNote>;
    FPendingNotes: TDictionary<Int64, TNote>;
    FLogger: ILogger;
    procedure OnTimer(Sender: TObject);
    function GetOnSave: TProc<TNote>;
    procedure SetOnSave(const Value: TProc<TNote>);
    function GetDelay: Integer;
    procedure SetDelay(const Value: Integer);
  public
    constructor Create(ADelay: Integer = 1000);
    destructor Destroy; override;
    procedure ScheduleSave(ANote: TNote);
    procedure CancelSave(const ANoteID: Int64);
    procedure Flush;
    property OnSave: TProc<TNote> read GetOnSave write SetOnSave;
    property Delay: Integer read GetDelay write SetDelay;
  end;

implementation

{ TAutosaveService }

constructor TAutosaveService.Create(ADelay: Integer = 1000);
begin
  inherited Create;
  FDelay := ADelay;
  FPendingNotes := TDictionary<Int64, TNote>.Create;
  FLogger := CreateLogger;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := FDelay;
  FTimer.OnTimer := OnTimer;
end;

destructor TAutosaveService.Destroy;
begin
  FTimer.Free;
  FPendingNotes.Free;
  inherited;
end;

procedure TAutosaveService.OnTimer(Sender: TObject);
var
  NoteID: Int64;
  Note: TNote;
begin
  FTimer.Enabled := False;
  try
    for NoteID in FPendingNotes.Keys do
    begin
      Note := FPendingNotes[NoteID];
      if Assigned(Note) and Assigned(FOnSave) then
      begin
        FLogger.Debug(Format('Autosave: Saving note ID %d', [NoteID]));
        FOnSave(Note);
      end;
    end;
  finally
    FPendingNotes.Clear;
  end;
end;

procedure TAutosaveService.ScheduleSave(ANote: TNote);
var
  NoteID: Int64;
begin
  NoteID := ANote.ID;
  if NoteID = 0 then Exit;
  FPendingNotes.AddOrSetValue(NoteID, ANote);
  FLogger.Debug(Format('Autosave: Scheduled save for note ID %d', [NoteID]));
  FTimer.Enabled := False;
  FTimer.Interval := FDelay;
  FTimer.Enabled := True;
end;

procedure TAutosaveService.CancelSave(const ANoteID: Int64);
begin
  FTimer.Enabled := False;
  FPendingNotes.Remove(ANoteID);
  FLogger.Debug(Format('Autosave: Canceled save for note ID %d', [ANoteID]));
end;

procedure TAutosaveService.Flush;
var
  NoteID: Int64;
  Note: TNote;
begin
  FTimer.Enabled := False;
  try
    for NoteID in FPendingNotes.Keys do
    begin
      Note := FPendingNotes[NoteID];
      if Assigned(Note) and Assigned(FOnSave) then
      begin
        FLogger.Debug(Format('Autosave: Flushing save for note ID %d', [NoteID]));
        FOnSave(Note);
      end;
    end;
  finally
    FPendingNotes.Clear;
  end;
end;

function TAutosaveService.GetOnSave: TProc<TNote>;
begin
  Result := FOnSave;
end;

procedure TAutosaveService.SetOnSave(const Value: TProc<TNote>);
begin
  FOnSave := Value;
end;

function TAutosaveService.GetDelay: Integer;
begin
  Result := FDelay;
end;

procedure TAutosaveService.SetDelay(const Value: Integer);
begin
  FDelay := Value;
  FTimer.Interval := FDelay;
end;

end.