unit uWebDavBackend;

// Phase 7E: a WebDAV ISyncBackend.
//
// Objects live one-per-file under the collection named by BaseUrl, keyed by
// name (note guid). Uses optimistic concurrency via ETags:
//   * ReadWithETag  -> GET, returns the response ETag header
//   * WriteIfMatch  -> PUT with If-Match: <etag>, or If-None-Match: * when no
//                      ETag is expected; a 412 Precondition Failed is reported
//                      as False so the engine can defer to the next run.
//
// Note: HTTP is synchronous, and SyncNow runs on the main thread, so a slow
// server will block the UI. Moving the sync work to a background thread is a
// tracked follow-up (see docs/PHASE_7_CLOUD_SYNC_DESIGN.md).

interface

uses
  System.SysUtils,
  System.Net.URLClient, System.Net.HttpClientComponent,
  uServiceInterfaces;

type
  TWebDavBackend = class(TInterfacedObject, ISyncBackend)
  private
    FBaseUrl: string;
    FUserName: string;
    FPassword: string;
    FClient: TNetHTTPClient;
    function UrlFor(const AName: string): string;
    function BareHeaders: TNetHeaders;
    function HeadersWith(const AName, AValue: string): TNetHeaders;
    procedure AppendHeader(var AHeaders: TNetHeaders; const AName, AValue: string);
  public
    constructor Create(const ABaseUrl, AUserName, APassword: string);
    destructor Destroy; override;
    function DisplayName: string;
    function ListNames: TArray<string>;
    function Read(const AName: string): string;
    procedure Write(const AName, AContent: string);
    procedure Remove(const AName: string);
    function SupportsETags: Boolean;
    function ReadWithETag(const AName: string; out AETag: string): string;
    function WriteIfMatch(const AName, AContent, AExpectedETag: string): Boolean;
  end;

implementation

uses
  System.Classes, System.Net.HttpClient, System.NetEncoding, System.StrUtils;

// Extracts the text of every <...href> element from a WebDAV multistatus body,
// tolerating namespace prefixes (D:href, d:href, href).
function ExtractHrefs(const AXml: string): TArray<string>;
var
  Lower: string;
  Search, OpenEnd, CloseStart: Integer;
  Href: string;
begin
  Result := nil;
  Lower := LowerCase(AXml);
  Search := 1;
  while True do
  begin
    Search := PosEx('href', Lower, Search);
    if Search = 0 then Break;
    OpenEnd := PosEx('>', AXml, Search);
    if OpenEnd = 0 then Break;
    CloseStart := PosEx('</', AXml, OpenEnd);
    if CloseStart = 0 then Break;
    Href := Trim(Copy(AXml, OpenEnd + 1, CloseStart - OpenEnd - 1));
    if Href <> '' then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Href;
    end;
    Search := CloseStart + 2;
  end;
end;

function EndsWithText(const AText, ASuffix: string): Boolean;
begin
  Result := (Length(AText) >= Length(ASuffix)) and
    SameText(Copy(AText, Length(AText) - Length(ASuffix) + 1, Length(ASuffix)), ASuffix);
end;

// Reduces an href (absolute path, relative path, or full URL) to the bare
// object name: the last path segment with a trailing '.json' removed.
function HrefToName(const AHref: string): string;
var
  Path: string;
  Slash: Integer;
begin
  Path := AHref;
  if (Path <> '') and (Path[Length(Path)] = '/') then
    Path := Copy(Path, 1, Length(Path) - 1);
  Slash := LastDelimiter('/', Path);
  if Slash > 0 then
    Path := Copy(Path, Slash + 1, MaxInt);
  Path := TNetEncoding.URL.Decode(Path);
  if EndsWithText(Path, '.json') then
    Path := Copy(Path, 1, Length(Path) - Length('.json'));
  Result := Path;
end;

{ TWebDavBackend }

constructor TWebDavBackend.Create(const ABaseUrl, AUserName, APassword: string);
begin
  inherited Create;
  FBaseUrl := ABaseUrl;
  if (FBaseUrl <> '') and (FBaseUrl[Length(FBaseUrl)] <> '/') then
    FBaseUrl := FBaseUrl + '/';
  FUserName := AUserName;
  FPassword := APassword;
  FClient := TNetHTTPClient.Create(nil);
end;

destructor TWebDavBackend.Destroy;
begin
  FClient.Free;
  inherited;
end;

function TWebDavBackend.DisplayName: string;
begin
  Result := FBaseUrl;
end;

function TWebDavBackend.UrlFor(const AName: string): string;
begin
  Result := FBaseUrl + AName + '.json';
end;

procedure TWebDavBackend.AppendHeader(var AHeaders: TNetHeaders; const AName, AValue: string);
begin
  SetLength(AHeaders, Length(AHeaders) + 1);
  AHeaders[High(AHeaders)] := TNetHeader.Create(AName, AValue);
end;

function TWebDavBackend.BareHeaders: TNetHeaders;
begin
  Result := nil;
  if FUserName <> '' then
    AppendHeader(Result, 'Authorization',
      'Basic ' + TNetEncoding.Base64.Encode(FUserName + ':' + FPassword));
end;

function TWebDavBackend.HeadersWith(const AName, AValue: string): TNetHeaders;
begin
  Result := BareHeaders;
  AppendHeader(Result, AName, AValue);
end;

function TWebDavBackend.ListNames: TArray<string>;
var
  Resp: IHTTPResponse;
  Body: string;
  Hrefs: TArray<string>;
  I: Integer;
  Name, Self_, Href: string;
begin
  Result := nil;
  Resp := FClient.Execute('PROPFIND', FBaseUrl, nil, nil, HeadersWith('Depth', '1'));
  if (Resp = nil) or (Resp.StatusCode < 200) or (Resp.StatusCode >= 300) then
    Exit(nil);
  Body := Resp.ContentAsString(TEncoding.UTF8);
  Self_ := HrefToName(FBaseUrl);
  Hrefs := ExtractHrefs(Body);
  for I := 0 to High(Hrefs) do
  begin
    Href := Hrefs[I];
    Name := HrefToName(Href);
    // Skip the collection itself and anything that is not a note object.
    if (Name = '') or (SameText(Name, Self_)) then Continue;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Name;
  end;
end;

function TWebDavBackend.ReadWithETag(const AName: string; out AETag: string): string;
var
  Resp: IHTTPResponse;
begin
  AETag := '';
  Result := '';
  Resp := FClient.Get(UrlFor(AName), nil, BareHeaders);
  if (Resp = nil) or (Resp.StatusCode < 200) or (Resp.StatusCode >= 300) then
    Exit(''); // 404 -> absent
  AETag := Resp.HeaderValue['ETag'];
  Result := Resp.ContentAsString(TEncoding.UTF8);
end;

function TWebDavBackend.Read(const AName: string): string;
var
  Tag: string;
begin
  Result := ReadWithETag(AName, Tag);
end;

function BodyStream(const AContent: string): TStream;
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(AContent);
  Result := TMemoryStream.Create;
  if Length(Bytes) > 0 then
    Result.WriteBuffer(Bytes[0], Length(Bytes));
  Result.Position := 0;
end;

function TWebDavBackend.WriteIfMatch(const AName, AContent, AExpectedETag: string): Boolean;
var
  Src: TStream;
  Resp: IHTTPResponse;
  Headers: TNetHeaders;
begin
  Headers := BareHeaders;
  if AExpectedETag = '' then
    AppendHeader(Headers, 'If-None-Match', '*')
  else
    AppendHeader(Headers, 'If-Match', AExpectedETag);
  AppendHeader(Headers, 'Content-Type', 'application/json; charset=utf-8');

  Src := BodyStream(AContent);
  try
    Resp := FClient.Execute('PUT', UrlFor(AName), Src, nil, Headers);
  finally
    Src.Free;
  end;
  // 412 Precondition Failed (or any non-2xx) -> the object was left untouched.
  Result := (Resp <> nil) and (Resp.StatusCode >= 200) and (Resp.StatusCode < 300);
end;

procedure TWebDavBackend.Write(const AName, AContent: string);
var
  Src: TStream;
begin
  Src := BodyStream(AContent);
  try
    FClient.Execute('PUT', UrlFor(AName), Src, nil,
      HeadersWith('Content-Type', 'application/json; charset=utf-8'));
  finally
    Src.Free;
  end;
end;

procedure TWebDavBackend.Remove(const AName: string);
begin
  FClient.Execute('DELETE', UrlFor(AName), nil, nil, BareHeaders);
end;

function TWebDavBackend.SupportsETags: Boolean;
begin
  Result := True;
end;

end.
