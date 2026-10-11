@echo off
rem AutoSetup_Win - chi sinh file unattend vao out\unattend (khong chep len USB).
rem Tham so truyen tiep cho scripts\TaoUnattend.ps1, vd: TAO_UNATTEND.bat -DiskId 0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\TaoUnattend.ps1" %*
