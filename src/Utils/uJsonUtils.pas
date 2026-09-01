unit uJsonUtils;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON,
  System.IOUtils, System.Types;

type
  TJsonUtils = class
  public
    class function LoadFromFile(const AFileName: string; out AJson: TJSONObject): Boolean;
    class function SaveToFile(const AFileName: string; const AJson: TJSONObject): Boolean;
    class function TryGetString(const AJson: TJSONObject; const APath: string; out AValue: string): Boolean;
    class function TryGetInteger(const AJson: TJSONObject; const APath: string; out AValue: Integer): Boolean;
    class function TryGetBoolean(const AJson: TJSONObject; const APath: string; out AValue: Boolean): Boolean;
    class function TryGetInt64(const AJson: TJSONObject; const APath: string; out AValue: Int64): Boolean;
    class function TryGetFloat(const AJson: TJSONObject; const APath: string; out AValue: Double): Boolean;
    class function TryGetObject(const AJson: TJSONObject; const APath: string; out AValue: TJSONObject): Boolean;
    class function TryGetArray(const AJson: TJSONObject; const APath: string; out AValue: TJSONArray): Boolean;
    class procedure SetValue(const AJson: TJSONObject; const APath: string; const AValue: string); overload;
    class procedure SetValue(const AJson: TJSONObject; const APath: string; const AValue: Integer); overload;
    class procedure SetValue(const AJson: TJSONObject; const APath: string; const AValue: Boolean); overload;
    class procedure SetValue(const AJson: TJSONObject; const APath: string; const AValue: Int64); overload;
    class procedure SetValue(const AJson: TJSONObject; const APath: string; const AValue: Double); overload;
    class function JsonToString(const AJson: TJsonValue; APretty: Boolean = True): string;
  end;

implementation

uses
  System.Rtti;

{ TJsonUtils }

class function TJsonUtils.LoadFromFile(const AFileName: string; out AJson: TJSONObject): Boolean;
var
  Text: string;
  Value: TJSONValue;
begin
  Result := False;
  AJson := nil;
  
  if not TFile.Exists(AFileName) then Exit;
  
  try
    Text := TFile.ReadAllText(AFileName, TEncoding.UTF8);
    Value := TJSONObject.ParseJSONValue(Text);
    if Value is TJSONObject then
    begin
      AJson := Value as TJSONObject;
      Result := True;
    end
    else
      Value.Free;
  except
    Result := False;
  end;
end;

class function TJsonUtils.SaveToFile(const AFileName: string; const AJson: TJSONObject): Boolean;
var
  Stream: TFileStream;
  Writer: TStreamWriter;
begin
  Result := False;
  try
    TDirectory.CreateDirectory(TPath.GetDirectoryName(AFileName));
    Stream := TFileStream.Create(AFileName, fmCreate or fmShareDenyWrite);
    try
      Writer := TStreamWriter.Create(Stream, TEncoding.UTF8);
      try
        Writer.Write(AJson.Format);
        Result := True;
      finally
        Writer.Free;
      end;
    finally
      Stream.Free;
    end;
  except
    Result := False;
  end;
end;

class function TJsonUtils.TryGetString(const AJson: TJSONObject; const APath: string; out AValue: string): Boolean;
var
  Value: TJSONValue;
begin
  Result := False;
  AValue := '';
  if AJson = nil then Exit;
  
  Value := AJson.GetValue(APath);
  if (Value <> nil) and (Value.Value <> '') then
  begin
    AValue := Value.Value;
    Result := True;
  end;
end;

class function TJsonUtils.TryGetInteger(const AJson: TJSONObject; const APath: string; out AValue: Integer): Boolean;
var
  Value: TJSONValue;
begin
  Result := False;
  AValue := 0;
  if AJson = nil then Exit;
  
  Value := AJson.GetValue(APath);
  if Value is TJSONNumber then
  begin
    AValue := (Value as TJSONNumber).AsInt;
    Result := True;
  end;
end;

class function TJsonUtils.TryGetBoolean(const AJson: TJSONObject; const APath: string; out AValue: Boolean): Boolean;
var
  Value: TJSONValue;
begin
  Result := False;
  AValue := False;
  if AJson = nil then Exit;
  
  Value := AJson.GetValue(APath);
  if Value is TJSONTrue then
  begin
    AValue := True;
    Result := True;
  end
  else if Value is TJSONFalse then
  begin
    AValue := False;
    Result := True;
  end;
end;

class function TJsonUtils.TryGetInt64(const AJson: TJSONObject; const APath: string; out AValue: Int64): Boolean;
var
  Value: TJSONValue;
begin
  Result := False;
  AValue := 0;
  if AJson = nil then Exit;
  
  Value := AJson.GetValue(APath);
  if Value is TJSONNumber then
  begin
    AValue := (Value as TJSONNumber).AsInt64;
    Result := True;
  end;
end;

class function TJsonUtils.TryGetFloat(const AJson: TJSONObject; const APath: string; out AValue: Double): Boolean;
var
  Value: TJSONValue;
begin
  Result := False;
  AValue := 0;
  if AJson = nil then Exit;
  
  Value := AJson.GetValue(APath);
  if Value is TJSONNumber then
  begin
    AValue := (Value as TJSONNumber).AsDouble;
    Result := True;
  end;
end;

class function TJsonUtils.TryGetObject(const AJson: TJSONObject; const APath: string; out AValue: TJSONObject): Boolean;
var
  Value: TJSONValue;
begin
  Result := False;
  AValue := nil;
  if AJson = nil then Exit;
  
  Value := AJson.GetValue(APath);
  if Value is TJSONObject then
  begin
    AValue := Value as TJSONObject;
    Result := True;
  end;
end;

class function TJsonUtils.TryGetArray(const AJson: TJSONObject; const APath: string; out AValue: TJSONArray): Boolean;
var
  Value: TJSONValue;
begin
  Result := False;
  AValue := nil;
  if AJson = nil then Exit;
  
  Value := AJson.GetValue(APath);
  if Value is TJSONArray then
  begin
    AValue := Value as TJSONArray;
    Result := True;
  end;
end;

class procedure TJsonUtils.SetValue(const AJson: TJSONObject; const APath: string; const AValue: string);
var
  Parts: TStringDynArray;
  Current: TJSONObject;
  I: Integer;
  Parent: TJSONObject;
  Key: string;
begin
  if AJson = nil then Exit;
  Parts := APath.Split(['.']);
  Current := AJson;
  
  for I := 0 to Length(Parts) - 2 do
  begin
    Key := Parts[I];
    if not Current.TryGetValue<TJSONObject>(Key, Parent) then
    begin
      Parent := TJSONObject.Create;
      Current.AddPair(Key, Parent);
    end;
    Current := Parent;
  end;
  
  Key := Parts[High(Parts)];
  Current.RemovePair(Key).Free;
  Current.AddPair(Key, AValue);
end;

class procedure TJsonUtils.SetValue(const AJson: TJSONObject; const APath: string; const AValue: Integer);
begin
  SetValue(AJson, APath, AValue.ToString);
end;

class procedure TJsonUtils.SetValue(const AJson: TJSONObject; const APath: string; const AValue: Boolean);
begin
  SetValue(AJson, APath, BoolToStr(AValue, True));
end;

class procedure TJsonUtils.SetValue(const AJson: TJSONObject; const APath: string; const AValue: Int64);
begin
  SetValue(AJson, APath, AValue.ToString);
end;

class procedure TJsonUtils.SetValue(const AJson: TJSONObject; const APath: string; const AValue: Double);
begin
  SetValue(AJson, APath, FloatToStr(AValue));
end;

class function TJsonUtils.JsonToString(const AJson: TJsonValue; APretty: Boolean): string;
begin
  if AJson = nil then
    Result := 'null'
  else if APretty then
    Result := AJson.Format
  else
    Result := AJson.ToString;
end;

end.