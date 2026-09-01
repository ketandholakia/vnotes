@echo off
echo ============================================
echo VNotes Test Build Script
echo ============================================

call "C:\Program Files (x86)\Embarcadero\Studio\21.0\Bin\rsvars.bat"

echo.
echo Cleaning test build artifacts...
cd /d D:\ketan\github\vnotes\tests
del /q *.dcu *.exe *.map *.rsm 2>nul
del /q Models\*.dcu 2>nul

echo.
echo Building test project...
echo.

REM DUnitX source path - REQUIRED for DUnitX units
SET DUNITX_PATH=C:\Program Files (x86)\Embarcadero\Studio\21.0\source\DunitX

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