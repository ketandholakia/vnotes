@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\21.0\Bin\rsvars.bat"
cd /d D:\ketan\github\vnotes\tests
dcc32 -B -Q -M -I.;"D:\ketan\github\vnotes\tests\Models";"D:\ketan\github\vnotes\src";"D:\ketan\github\vnotes\src\Models";"D:\ketan\github\vnotes\src\Controllers";"D:\ketan\github\vnotes\src\Storage";"D:\ketan\github\vnotes\src\Services";"D:\ketan\github\vnotes\src\Utils";"D:\ketan\github\vnotes\src\Forms";"D:\ketan\github\vnotes\src\Utils" StickyNotes.Tests.dpr 2>&1