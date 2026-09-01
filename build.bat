@echo off
REM ============================================================
REM VNotes canonical build script (Win32 Debug).
REM Self-configures the Delphi toolchain (rsvars.bat) so a plain
REM cmd shell works without manual PATH setup.
REM
REM Usage:  build.bat
REM Output: src\Win32\Debug\StickyNotes.exe
REM ============================================================

REM --- Locate Delphi toolchain (DELPHI_ROOT wins; else probe 23.0,22.0,21.0) ---
set "DELPHI_BIN="
if defined DELPHI_ROOT if exist "%DELPHI_ROOT%\bin\rsvars.bat" set "DELPHI_BIN=%DELPHI_ROOT%\bin\rsvars.bat"
if not defined DELPHI_BIN if exist "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat" set "DELPHI_BIN=C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
if not defined DELPHI_BIN if exist "C:\Program Files (x86)\Embarcadero\Studio\22.0\bin\rsvars.bat" set "DELPHI_BIN=C:\Program Files (x86)\Embarcadero\Studio\22.0\bin\rsvars.bat"
if not defined DELPHI_BIN if exist "C:\Program Files (x86)\Embarcadero\Studio\21.0\bin\rsvars.bat" set "DELPHI_BIN=C:\Program Files (x86)\Embarcadero\Studio\21.0\bin\rsvars.bat"
if not defined DELPHI_BIN goto :nofound

echo [Toolchain] Using %DELPHI_BIN%
call "%DELPHI_BIN%"
if errorlevel 1 exit /b 1

REM --- Report resolved dcc32 (absorbs check_version.bat) ---
where dcc32
dcc32 2>&1 | findstr /i "compiler version"

cd /d "%~dp0src"

REM Ensure the -N output dir exists (dcc32 does not auto-create it)
if not exist "Win32\Debug" mkdir "Win32\Debug"

REM -B full rebuild, -Q quiet, -M build dependent units,
REM -I include paths, -U unit search path, -N .dcu output dir.
REM (redundant hard-coded D:\ketan\...\src\Utils path dropped for portability)
dcc32 -B -Q -M -I.;Models;Controllers;Storage;Services;Utils;Forms -UWin32\Debug -NWin32\Debug StickyNotes.dpr 2>&1

exit /b %ERRORLEVEL%

:nofound
echo [ERROR] Delphi toolchain not found. Tried:
echo   %%DELPHI_ROOT%%\bin\rsvars.bat
echo   C:\Program Files ^(x86^)\Embarcadero\Studio\23.0\bin\rsvars.bat
echo   C:\Program Files ^(x86^)\Embarcadero\Studio\22.0\bin\rsvars.bat
echo   C:\Program Files ^(x86^)\Embarcadero\Studio\21.0\bin\rsvars.bat
exit /b 1
