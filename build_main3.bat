@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\21.0\Bin\rsvars.bat"
cd /d D:\ketan\github\vnotes\src
dcc32 -B -Q -M -I.;Models;Controllers;Storage;Services;Utils;Forms;"D:\ketan\github\vnotes\src\Utils" -UWin32\Debug -NWin32\Debug StickyNotes.dpr 2>&1