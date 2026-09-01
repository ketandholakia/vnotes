unit uThemeService;

interface

uses
  System.SysUtils, System.Classes, Vcl.Graphics, Vcl.Themes, Vcl.Styles,
  uEnums;

type
  TThemeService = class
  private
    FDarkTheme: Boolean;
    FNoteColors: array[TNoteColor] of TColor;
    FNoteColorsDark: array[TNoteColor] of TColor;
    procedure InitializeColors;
  public
    constructor Create;
    procedure SetDarkTheme(ADark: Boolean);
    function GetNoteColor(ANoteColor: TNoteColor): TColor;
    function GetNoteTextColor(ANoteColor: TNoteColor): TColor;
    function GetBackgroundColor: TColor;
    function GetTextColor: TColor;
    function GetBorderColor: TColor;
    function GetButtonColor: TColor;
    function GetButtonTextColor: TColor;
    function GetHighlightColor: TColor;
    property DarkTheme: Boolean read FDarkTheme;
  end;

implementation

{ TThemeService }

constructor TThemeService.Create;
begin
  inherited;
  InitializeColors;
  FDarkTheme := False;
end;

procedure TThemeService.InitializeColors;
begin
  // Light theme colors (standard sticky note colors)
  FNoteColors[ncYellow] := $0080FFFF;  // BGR: $FFFF80
  FNoteColors[ncGreen]  := $0080FF80;  // BGR: $80FF80
  FNoteColors[ncBlue]   := $00FFC080;  // BGR: $80C0FF
  FNoteColors[ncPink]   := $00C080FF;  // BGR: $FF80C0
  FNoteColors[ncPurple] := $00FF80FF;  // BGR: $FF80FF
  FNoteColors[ncOrange] := $0080C0FF;  // BGR: $FFC080
  FNoteColors[ncWhite]  := $00FFFFFF;
  FNoteColors[ncGray]   := $00E0E0E0;

  // Dark theme colors - muted versions
  FNoteColorsDark[ncYellow] := $00408080;  // Dark yellow
  FNoteColorsDark[ncGreen]  := $00408040;  // Dark green
  FNoteColorsDark[ncBlue]   := $00806040;  // Dark blue
  FNoteColorsDark[ncPink]   := $00804060;  // Dark pink
  FNoteColorsDark[ncPurple] := $00804080;  // Dark purple
  FNoteColorsDark[ncOrange] := $00406080;  // Dark orange
  FNoteColorsDark[ncWhite]  := $00404040;  // Dark gray
  FNoteColorsDark[ncGray]   := $00303030;  // Darker gray
end;

procedure TThemeService.SetDarkTheme(ADark: Boolean);
begin
  FDarkTheme := ADark;
  if ADark then
  begin
    try
      TStyleManager.TrySetStyle('Windows10 Dark');
    except
      TStyleManager.TrySetStyle('Dark');
    end;
  end
  else
  begin
    TStyleManager.TrySetStyle('Windows10');
  end;
end;

function TThemeService.GetNoteColor(ANoteColor: TNoteColor): TColor;
begin
  if FDarkTheme then
    Result := FNoteColorsDark[ANoteColor]
  else
    Result := FNoteColors[ANoteColor];
end;

function TThemeService.GetNoteTextColor(ANoteColor: TNoteColor): TColor;
begin
  if FDarkTheme then
    Result := clWhite
  else
    Result := clBlack;
end;

function TThemeService.GetBackgroundColor: TColor;
begin
  if FDarkTheme then
    Result := $002D2D2D
  else
    Result := clWindow;
end;

function TThemeService.GetTextColor: TColor;
begin
  if FDarkTheme then
    Result := clWhite
  else
    Result := clWindowText;
end;

function TThemeService.GetBorderColor: TColor;
begin
  if FDarkTheme then
    Result := $00505050
  else
    Result := clBtnShadow;
end;

function TThemeService.GetButtonColor: TColor;
begin
  if FDarkTheme then
    Result := $003D3D3D
  else
    Result := clBtnFace;
end;

function TThemeService.GetButtonTextColor: TColor;
begin
  if FDarkTheme then
    Result := clWhite
  else
    Result := clBtnText;
end;

function TThemeService.GetHighlightColor: TColor;
begin
  if FDarkTheme then
    Result := $000078D7
  else
    Result := clHighlight;
end;

end.