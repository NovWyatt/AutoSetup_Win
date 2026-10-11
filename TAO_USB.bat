@echo off
rem AutoSetup_Win - sinh file unattend tu cau-hinh\CauHinh.json roi chep len USB Ventoy.
rem Tham so truyen tiep cho scripts\TaoUSB.ps1, vd: TAO_USB.bat -O E: -ChayThu
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\TaoUSB.ps1" %*
