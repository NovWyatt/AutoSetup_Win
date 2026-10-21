@echo off
rem AutoSetup_Win - giao dien tao USB cai Windows: cai Ventoy, chep ISO, sua cau hinh, chep AutoSetup len USB.
rem Tu xin quyen quan tri (can de cai Ventoy). Tham so truyen tiep cho scripts\GiaoDienUSB.ps1, vd: -O E:
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0scripts\GiaoDienUSB.ps1" %*
