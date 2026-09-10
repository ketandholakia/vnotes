program ScrollProbe;
{$APPTYPE CONSOLE}
{ Verifies whether GetScrollInfo(SB_VERT) returns meaningful data on a
  multiline EDIT control:
    1) without WS_VSCROLL (equivalent to TMemo.ScrollBars := ssNone)
    2) with WS_VSCROLL, then hidden via ShowScrollBar(SB_VERT, False)
    3) with WS_VSCROLL visible
  Uses 200 lines of text in a ~10-line-tall window. }

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils;

procedure Report(const ATitle: string; H: HWND);
var
  SI: TScrollInfo;
begin
  FillChar(SI, SizeOf(SI), 0);
  SI.cbSize := SizeOf(SI);
  SI.fMask  := SIF_ALL;
  if GetScrollInfo(H, SB_VERT, SI) then
    Writeln(Format('%-28s: OK   nMax=%d nPage=%d nPos=%d',
      [ATitle, SI.nMax, SI.nPage, SI.nPos]))
  else
    Writeln(Format('%-28s: FAIL GetLastError=%d', [ATitle, GetLastError]));
end;

function MakeEdit(const AText: string; AStyle: DWORD; AParent: HWND): HWND;
begin
  Result := CreateWindowEx(0, 'EDIT', PChar(AText),
    WS_CHILD or WS_VISIBLE or AStyle,
    0, 0, 300, 150, AParent, 0, HInstance, nil);
end;

var
  I: Integer;
  Text: string;
  H1, H2, H3, HParent: HWND;
begin
  try
    HParent := CreateWindowEx(0, 'EDIT', nil, WS_POPUP,
      0, 0, 10, 10, 0, 0, HInstance, nil);
    if HParent = 0 then
    begin
      Writeln('parent creation failed');
      Exit;
    end;
    Text := '';
    for I := 1 to 200 do
      Text := Text + 'line ' + IntToStr(I) + #13#10;

    H1 := MakeEdit(Text, ES_MULTILINE or ES_AUTOVSCROLL or ES_LEFT, HParent);
    Report('no WS_VSCROLL (ssNone)', H1);

    H2 := MakeEdit(Text, ES_MULTILINE or ES_AUTOVSCROLL or ES_LEFT or WS_VSCROLL, HParent);
    ShowScrollBar(H2, SB_VERT, False); // hide, style remains
    Report('WS_VSCROLL + ShowScrollBar(False)', H2);

    H3 := MakeEdit(Text, ES_MULTILINE or ES_AUTOVSCROLL or ES_LEFT or WS_VSCROLL, HParent);
    Report('WS_VSCROLL visible', H3);

    // Also check after forcing a repaint cycle / idle update on H1
    UpdateWindow(H1);
    Report('no WS_VSCROLL after UpdateWindow', H1);

    DestroyWindow(H1);
    DestroyWindow(H2);
    DestroyWindow(H3);
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
