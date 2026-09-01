@echo off
echo ============================================
echo VNotes Test Build Script
echo ============================================
echo.
REM --- Locate Delphi toolchain (same bootstrap as build.bat) ---
set "DELPHI_BIN="
if defined DELPHI_ROOT if exist "%DELPHI_ROOT%\bin\rsvars.bat" set "DELPHI_BIN=%DELPHI_ROOT%\bin\rsvars.bat"
if not defined DELPHI_BIN if exist "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat" set "DELPHI_BIN=C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
if not defined DELPHI_BIN if exist "C:\Program Files (x86)\Embarcadero\Studio\22.0\bin\rsvars.bat" set "DELPHI_BIN=C:\Program Files (x86)\Embarcadero\Studio\22.0\bin\rsvars.bat"
if not defined DELPHI_BIN if exist "C:\Program Files (x86)\Embarcadero\Studio\21.0\bin\rsvars.bat" set "DELPHI_BIN=C:\Program Files (x86)\Embarcadero\Studio\21.0\bin\rsvars.bat"
if not defined DELPHI_BIN goto :nofound

echo [Toolchain] Using %DELPHI_BIN%
call "%DELPHI_BIN%"
if errorlevel 1 exit /b 1

REM Derive DUnitX path from the resolved Delphi root (parent of bin)
for %%I in ("%DELPHI_BIN%") do set "DELPHI_ROOT=%%~dpI.."
set "DUNITX_PATH=%DELPHI_ROOT%\source\DunitX"
echo [Toolchain] DUnitX:   %DUNITX_PATH%

echo.
echo Cleaning test build artifacts...
cd /d "%~dp0tests"
del /q *.dcu *.exe *.map *.rsm 2>nul
del /q Models\*.dcu 2>nul

echo.
echo Building test project...
echo.

REM Build command with all necessary search paths:
REM - DUnitX source path (for DUnitX.TestFramework, etc.)
REM - Test models directory
REM - Source directories
dcc32 -B -Q -M ^
  -U"%DUNITX_PATH%" ^
  -U"Models" ^
  -U"..\src\Models" ^
  -U"..\src\Storage" ^
  -U"..\src\Controllers" ^
  -U"..\src\Services" ^
  -U"..\src\Application" ^
  -U"..\src\Utils" ^
  StickyNotes.Tests.dpr

SET BUILD_RESULT=%ERRORLEVEL%

echo.
if %BUILD_RESULT%==0 (
  echo ============================================
  echo BUILD SUCCESSFUL
  echo ============================================
) else (
  echo ============================================
  echo BUILD FAILED (Error code: %BUILD_RESULT%)
  echo ============================================
)

exit /b %BUILD_RESULT%

:nofound
echo [ERROR] Delphi toolchain not found. Tried:
echo   %%DELPHI_ROOT%%\bin\rsvars.bat
echo   C:\Program Files ^(x86^)\Embarcadero\Studio\23.0\bin\rsvars.bat
echo   C:\Program Files ^(x86^)\Embarcadero\Studio\22.0\bin\rsvars.bat
echo   C:\Program Files ^(x86^)\Embarcadero\Studio\21.0\bin\rsvars.bat
exit /b 1
