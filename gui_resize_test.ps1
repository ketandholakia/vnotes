# V-Notes resize GUI test driver (real Win32 input simulation; all Win32 in C#)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class GT {
  public struct RECT { public int L, T, R, B; }
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  static List<long> FindInPid(int pid, string cls) {
    var res = new List<long>();
    EnumWindows((h, l) => {
      int wpid; GetWindowThreadProcessId(h, out wpid);
      if (wpid == pid) {
        var sb = new StringBuilder(256); GetClassName(h, sb, 256);
        if (sb.ToString() == cls && IsWindowVisible(h)) res.Add(h.ToInt64());
      }
      return true;
    }, IntPtr.Zero);
    return res;
  }
  public static long FirstNoteHwnd(int pid) {
    var l = FindInPid(pid, "TNoteForm");
    return l.Count > 0 ? l[0] : 0;
  }
  public static string Style(long hwnd) {
    uint s = (uint)GetWindowLong((IntPtr)hwnd, -16);
    return "0x" + s.ToString("X8") + " WS_THICKFRAME=" + ((s & 0x00040000) != 0);
  }
  public static string RectStr(long hwnd) {
    RECT r; GetWindowRect((IntPtr)hwnd, out r);
    return r.L + "," + r.T + "," + r.R + "," + r.B + " (W=" + (r.R - r.L) + " H=" + (r.B - r.T) + ")";
  }
  public static int HitTest(long hwnd, int x, int y) {
    IntPtr res = SendMessage((IntPtr)hwnd, 0x0084, IntPtr.Zero, (IntPtr)((y << 16) | (x & 0xFFFF)));
    return (int)res;
  }
  public static void Drag(int x1, int y1, int x2, int y2) {
    SetCursorPos(x1, y1); System.Threading.Thread.Sleep(150);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(120);
    for (int i = 1; i <= 12; i++) {
      SetCursorPos(x1 + (x2 - x1) * i / 12, y1 + (y2 - y1) * i / 12);
      System.Threading.Thread.Sleep(40);
    }
    System.Threading.Thread.Sleep(120);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(250);
  }
  public static void CloseNote(long hwnd) {
    PostMessage((IntPtr)hwnd, 0x0010, IntPtr.Zero, IntPtr.Zero);
  }
}
"@

$exe = 'd:\ketan\github\vnotes\src\StickyNotes.exe'
$notesDir = "$env:APPDATA\StickyNotes\notes"
$snapDir = Join-Path $env:TEMP ('StickyNotes_notes_snap_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))

function Get-RectOf([long]$h) {
  $parts = [GT]::RectStr($h) -replace '[^0-9,].*$','' -split ','
  [pscustomobject]@{ L=[int]$parts[0]; T=[int]$parts[1]; R=[int]$parts[2]; B=[int]$parts[3] }
}
function Wait-Note($p) {
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep 1
    $h = [GT]::FirstNoteHwnd($p.Id)
    if ($h -ne 0) { return $h }
  }
  return [long]0
}

# --- 0. stop any running instance, snapshot user notes (BEFORE tests) ---
Get-Process StickyNotes -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 1
New-Item -ItemType Directory -Path $snapDir -Force | Out-Null

$beforeCount = 0
if (Test-Path $notesDir) {
  $beforeCount = @(Get-ChildItem -Path "$notesDir\*.json" -File -ErrorAction SilentlyContinue).Count
}

# Safety: never delete the only copy. Abort if there is nothing to snapshot.
if ($beforeCount -eq 0) {
  throw "SNAPSHOT ABORTED: zero note files found in '$notesDir' - nothing to back up; refusing to run (would risk deleting the only copy)."
}

# Snapshot BEFORE any test activity or deletion.
Copy-Item "$notesDir\*.json" $snapDir -ErrorAction Stop
$snapCount = @(Get-ChildItem -Path "$snapDir\*.json" -File -ErrorAction SilentlyContinue).Count
if ($snapCount -ne $beforeCount) {
  throw "SNAPSHOT FAILED: copied $snapCount file(s) but expected $beforeCount from '$notesDir'; aborting before any deletion."
}
Remove-Item "$notesDir\*.json" -Force
Write-Host "SNAPSHOT: $snapCount note file(s) backed up to $snapDir (beforeCount=$beforeCount)"

# --- 1. launch app against the clean store ---
Start-Process $exe
Start-Sleep 4
$proc = Get-Process StickyNotes -ErrorAction Stop
$noteHwnd = Wait-Note $proc
if ($noteHwnd -eq 0) { throw 'No visible TNoteForm found' }
Write-Host "NOTE_HWND=$noteHwnd"
Write-Host "GWL_STYLE: $([GT]::Style($noteHwnd))"

# --- 2. WM_NCHITTEST probes ---
$r = Get-RectOf $noteHwnd
$cx = [int](($r.L + $r.R) / 2); $cy = [int](($r.T + $r.B) / 2)
$probeList = @(
  @('right-edge',    ($r.R - 2), $cy),
  @('left-edge',     ($r.L + 2), $cy),
  @('bottom-edge',   $cx, ($r.B - 2)),
  @('top-edge',      $cx, ($r.T + 2)),
  @('top-left-cor',  ($r.L + 3), ($r.T + 3)),
  @('top-right-cor', ($r.R - 3), ($r.T + 3)),
  @('bottom-left',   ($r.L + 3), ($r.B - 3)),
  @('bottom-right',  ($r.R - 3), ($r.B - 3)),
  @('header-center', ($r.L + 80), ($r.T + 15)),
  @('center',        $cx, $cy)
)
foreach ($p in $probeList) {
  $ht = [GT]::HitTest($noteHwnd, [int]$p[1], [int]$p[2])
  Write-Host ("HITTEST {0,-14} @({1},{2}) -> {3}" -f $p[0], $p[1], $p[2], $ht)
}

# --- 3. resize drags (real input) ---
function Test-Resize([string]$name, [scriptblock]$fromPt, [scriptblock]$toPt) {
  $r0 = Get-RectOf $noteHwnd
  $f = & $fromPt $r0; $t = & $toPt $r0
  [GT]::Drag([int]$f[0], [int]$f[1], [int]$t[0], [int]$t[1])
  $r1 = Get-RectOf $noteHwnd
  $dw = ($r1.R - $r1.L) - ($r0.R - $r0.L)
  $dh = ($r1.B - $r1.T) - ($r0.B - $r0.T)
  Write-Host ("RESIZE {0,-12} dW={1,5} dH={2,5} dL={3,5} dT={4,5}" -f $name, $dw, $dh, ($r1.L - $r0.L), ($r1.T - $r0.T))
}

Test-Resize 'right' { param($r) @(($r.R - 2), [int](($r.T + $r.B) / 2)) } { param($r) @(($r.R + 140), [int](($r.T + $r.B) / 2)) }
Test-Resize 'bottom' { param($r) @([int](($r.L + $r.R) / 2), ($r.B - 2)) } { param($r) @([int](($r.L + $r.R) / 2), ($r.B + 110)) }
Test-Resize 'bottom-right' { param($r) @(($r.R - 3), ($r.B - 3)) } { param($r) @(($r.R + 60), ($r.B + 90)) }
Test-Resize 'left' { param($r) @(($r.L + 2), [int](($r.T + $r.B) / 2)) } { param($r) @(($r.L - 90), [int](($r.T + $r.B) / 2)) }
Test-Resize 'top' { param($r) @([int](($r.L + $r.R) / 2), ($r.T + 2)) } { param($r) @([int](($r.L + $r.R) / 2), ($r.T - 70)) }
Test-Resize 'top-left' { param($r) @(($r.L + 3), ($r.T + 3)) } { param($r) @(($r.L - 50), ($r.T - 60)) }
Test-Resize 'bottom-left' { param($r) @(($r.L + 3), ($r.B - 3)) } { param($r) @(($r.L - 40), ($r.B + 50)) }
Test-Resize 'top-right' { param($r) @(($r.R - 3), ($r.T + 3)) } { param($r) @(($r.R + 45), ($r.T - 55)) }
Test-Resize 'min-clamp' { param($r) @(($r.R - 2), [int](($r.T + $r.B) / 2)) } { param($r) @(($r.R - 800), [int](($r.T + $r.B) / 2)) }

# --- 4. header drag (move) ---
$r0 = Get-RectOf $noteHwnd
[GT]::Drag(($r0.L + 40), ($r0.T + 15), ($r0.L + 40), ($r0.T - 60))
$r1 = Get-RectOf $noteHwnd
Write-Host ("HEADER-DRAG dL={0} dT={1} dW={2} dH={3}" -f ($r1.L - $r0.L), ($r1.T - $r0.T), (($r1.R - $r1.L) - ($r0.R - $r0.L)), (($r1.B - $r1.T) - ($r0.B - $r0.T)))

# --- 5. persistence: close note (saves geometry), relaunch, measure ---
$sizeBefore = Get-RectOf $noteHwnd
$sizeBeforeStr = [GT]::RectStr($noteHwnd)
[GT]::CloseNote($noteHwnd)
Start-Sleep 2
Get-Process StickyNotes -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 1
Start-Process $exe
Start-Sleep 4
$proc2 = Get-Process StickyNotes
$note2 = Wait-Note $proc2
if ($note2 -ne 0) {
  $sizeAfter = Get-RectOf $note2
  Write-Host ("PERSIST before: " + $sizeBeforeStr)
  Write-Host ("PERSIST after : " + [GT]::RectStr($note2))
} else {
  Write-Host 'PERSIST FAILED: no note window after relaunch'
}
Start-Sleep 1
Get-Process StickyNotes -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 1

# --- restore user notes (AFTER tests) ---
if (Test-Path $notesDir) {
  Remove-Item "$notesDir\*.json" -Force -ErrorAction SilentlyContinue
} else {
  New-Item -ItemType Directory -Path $notesDir -Force | Out-Null
}
Copy-Item "$snapDir\*.json" $notesDir -ErrorAction Stop
$afterCount = @(Get-ChildItem -Path "$notesDir\*.json" -File -ErrorAction SilentlyContinue).Count
Write-Host "RESTORED: $afterCount note file(s)"
if ($afterCount -ne $beforeCount) {
  throw "RESTORE MISMATCH: expected $beforeCount note file(s) after restore, found $afterCount."
}
Write-Host 'DONE'
