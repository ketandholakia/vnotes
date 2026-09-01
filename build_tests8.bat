@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\21.0\Bin\rsvars.bat"
cd /d D:\ketan\github\vnotes\tests
dcc32 -B -Q -M -I.;"D:\ketan\github\vnotes\tests\Models" StickyNotes.Tests.dpr 2>&1