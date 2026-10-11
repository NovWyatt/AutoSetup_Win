@echo off
rem AutoSetup_Win - chay moi bai thu (khong doi may). Tham so truyen tiep, vd: CHAY_KIEM_THU.bat -Chi 3 -ChiTiet
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ChayTatCa.ps1" %*
pause
