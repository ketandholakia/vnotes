unit uColorUtils;

interface

uses
  Winapi.Windows, Vcl.Graphics, System.SysUtils, System.Math,
  uEnums;

type
  TColorUtils = class
  public
    class function LightenColor(AColor: TColor; AAmount: Integer): TColor;
    class function DarkenColor(AColor: TColor; AAmount: Integer): TColor;
    class function GetContrastColor(ABackground: TColor): TColor;
    class function ColorToHex(AColor: TColor): string;
    class function HexToColor(const AHex: string): TColor;
    class function BlendColors(AColor1, AColor2: TColor; AAlpha: Single): TColor;
    class function IsDarkColor(AColor: TColor): Boolean;
    class function AdjustBrightness(AColor: TColor; APercent: Integer): TColor;
    class function GetComplementaryColor(AColor: TColor): TColor;
  end;

implementation

{ TColorUtils }

class function TColorUtils.LightenColor(AColor: TColor; AAmount: Integer): TColor;
var
  R, G, B: Byte;
begin
  R := GetRValue(AColor);
  G := GetGValue(AColor);
  B := GetBValue(AColor);
  
  R := Min(255, R + AAmount);
  G := Min(255, G + AAmount);
  B := Min(255, B + AAmount);
  
  Result := RGB(R, G, B);
end;

class function TColorUtils.DarkenColor(AColor: TColor; AAmount: Integer): TColor;
var
  R, G, B: Byte;
begin
  R := GetRValue(AColor);
  G := GetGValue(AColor);
  B := GetBValue(AColor);
  
  R := Max(0, R - AAmount);
  G := Max(0, G - AAmount);
  B := Max(0, B - AAmount);
  
  Result := RGB(R, G, B);
end;

class function TColorUtils.GetContrastColor(ABackground: TColor): TColor;
var
  Luminance: Double;
  R, G, B: Byte;
begin
  R := GetRValue(ABackground);
  G := GetGValue(ABackground);
  B := GetBValue(ABackground);
  
  // Calculate relative luminance (WCAG formula)
  Luminance := (0.299 * R + 0.587 * G + 0.114 * B) / 255;
  
  if Luminance > 0.5 then
    Result := clBlack
  else
    Result := clWhite;
end;

class function TColorUtils.ColorToHex(AColor: TColor): string;
begin
  Result := Format('#%.2x%.2x%.2x', [GetRValue(AColor), GetGValue(AColor), GetBValue(AColor)]);
end;

class function TColorUtils.HexToColor(const AHex: string): TColor;
var
  Hex: string;
  R, G, B: Integer;
begin
  Result := clWhite;
  Hex := AHex;
  
  if Hex.StartsWith('#') then
    Hex := Hex.Substring(1);
  
  if Length(Hex) = 6 then
  begin
    try
      R := StrToInt('$' + Hex.Substring(0, 2));
      G := StrToInt('$' + Hex.Substring(2, 2));
      B := StrToInt('$' + Hex.Substring(4, 2));
      Result := RGB(R, G, B);
    except
      Result := clWhite;
    end;
  end;
end;

class function TColorUtils.BlendColors(AColor1, AColor2: TColor; AAlpha: Single): TColor;
var
  R1, G1, B1: Byte;
  R2, G2, B2: Byte;
  R, G, B: Byte;
begin
  R1 := GetRValue(AColor1);
  G1 := GetGValue(AColor1);
  B1 := GetBValue(AColor1);
  
  R2 := GetRValue(AColor2);
  G2 := GetGValue(AColor2);
  B2 := GetBValue(AColor2);
  
  R := Round(R1 * (1 - AAlpha) + R2 * AAlpha);
  G := Round(G1 * (1 - AAlpha) + G2 * AAlpha);
  B := Round(B1 * (1 - AAlpha) + B2 * AAlpha);
  
  Result := RGB(R, G, B);
end;

class function TColorUtils.IsDarkColor(AColor: TColor): Boolean;
var
  Luminance: Double;
  R, G, B: Byte;
begin
  R := GetRValue(AColor);
  G := GetGValue(AColor);
  B := GetBValue(AColor);
  
  Luminance := (0.299 * R + 0.587 * G + 0.114 * B) / 255;
  Result := Luminance < 0.5;
end;

class function TColorUtils.AdjustBrightness(AColor: TColor; APercent: Integer): TColor;
var
  R, G, B: Byte;
  Factor: Double;
begin
  R := GetRValue(AColor);
  G := GetGValue(AColor);
  B := GetBValue(AColor);
  
  Factor := 1 + (APercent / 100.0);
  
  R := Min(255, Max(0, Round(R * Factor)));
  G := Min(255, Max(0, Round(G * Factor)));
  B := Min(255, Max(0, Round(B * Factor)));
  
  Result := RGB(R, G, B);
end;

class function TColorUtils.GetComplementaryColor(AColor: TColor): TColor;
var
  R, G, B: Byte;
begin
  R := GetRValue(AColor);
  G := GetGValue(AColor);
  B := GetBValue(AColor);
  
  Result := RGB(255 - R, 255 - G, 255 - B);
end;

end.