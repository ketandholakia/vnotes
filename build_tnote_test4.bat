@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\21.0\Bin\rsvars.bat"
cd /d D:\ketan\github\vnotes
dcc32 -B -Q -M -I.;src;src\Models;src\Controllers;src\Storage;src\Services;src\Utils;src\Forms;src\Utils tests\Models\TNoteTests.pas 2>&1