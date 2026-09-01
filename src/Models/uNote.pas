unit uNote;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Graphics, System.Types,
  uEnums;

type
  TNote = class
  private
    FID: Int64;
    FTitle: string;
    FContent: string;
    FColor: TNoteColor;
    FLeft: Integer;
    FTop: Integer;
    FWidth: Integer;
    FHeight: Integer;
    FAlwaysOnTop: Boolean;
    FCollapsed: Boolean;
    FLocked: Boolean;
    FCreatedAt: TDateTime;
    FUpdatedAt: TDateTime;
    function GetColorAsTColor: TColor;
    procedure SetColorAsTColor(const Value: TColor);
  public
    constructor Create; overload;
    constructor Create(AID: Int64; const ATitle, AContent: string; AColor: TNoteColor); overload;
    procedure Assign(Source: TNote);
    function Clone: TNote;
    property ID: Int64 read FID write FID;
    property Title: string read FTitle write FTitle;
    property Content: string read FContent write FContent;
    property Color: TNoteColor read FColor write FColor;
    property ColorAsTColor: TColor read GetColorAsTColor write SetColorAsTColor;
    property Left: Integer read FLeft write FLeft;
    property Top: Integer read FTop write FTop;
    property Width: Integer read FWidth write FWidth;
    property Height: Integer read FHeight write FHeight;
    property AlwaysOnTop: Boolean read FAlwaysOnTop write FAlwaysOnTop;
    property Collapsed: Boolean read FCollapsed write FCollapsed;
    property Locked: Boolean read FLocked write FLocked;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property UpdatedAt: TDateTime read FUpdatedAt write FUpdatedAt;
    function IsEmpty: Boolean;
    function GetBounds: TRect;
    procedure SetBounds(const ALeft, ATop, AWidth, AHeight: Integer);
    procedure Touch;
  end;

  TNoteList = TObjectList<TNote>;

implementation

{ TNote }

constructor TNote.Create;
begin
  inherited;
  FID := 0;
  FTitle := '';
  FContent := '';
  FColor := ncYellow;
  FLeft := 100;
  FTop := 100;
  FWidth := 300;
  FHeight := 250;
  FAlwaysOnTop := False;
  FCollapsed := False;
  FLocked := False;
  FCreatedAt := Now;
  FUpdatedAt := Now;
end;

constructor TNote.Create(AID: Int64; const ATitle, AContent: string; AColor: TNoteColor);
begin
  Create;
  FID := AID;
  FTitle := ATitle;
  FContent := AContent;
  FColor := AColor;
end;

procedure TNote.Assign(Source: TNote);
begin
  if Source = nil then Exit;
  FID := Source.FID;
  FTitle := Source.FTitle;
  FContent := Source.FContent;
  FColor := Source.FColor;
  FLeft := Source.FLeft;
  FTop := Source.FTop;
  FWidth := Source.FWidth;
  FHeight := Source.FHeight;
  FAlwaysOnTop := Source.FAlwaysOnTop;
  FCollapsed := Source.FCollapsed;
  FLocked := Source.FLocked;
  FCreatedAt := Source.FCreatedAt;
  FUpdatedAt := Source.FUpdatedAt;
end;

function TNote.Clone: TNote;
begin
  Result := TNote.Create;
  Result.Assign(Self);
end;

function TNote.GetColorAsTColor: TColor;
begin
  Result := NoteColorToColor(FColor);
end;

procedure TNote.SetColorAsTColor(const Value: TColor);
begin
  FColor := ColorToNoteColor(Value);
end;

function TNote.IsEmpty: Boolean;
begin
  Result := (FTitle = '') and (FContent = '');
end;

function TNote.GetBounds: TRect;
begin
  Result := Rect(FLeft, FTop, FLeft + FWidth, FTop + FHeight);
end;

procedure TNote.SetBounds(const ALeft, ATop, AWidth, AHeight: Integer);
begin
  FLeft := ALeft;
  FTop := ATop;
  FWidth := AWidth;
  FHeight := AHeight;
  Touch;
end;

procedure TNote.Touch;
begin
  FUpdatedAt := Now;
end;

end.