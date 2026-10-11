@echo off
rem AutoSetup_Win - chay lai buoc sau cai Windows (can quyen Admin, tu hoi UAC).
rem   CHAY_LAI.bat                       chay tiep cac buoc chua xong
rem   CHAY_LAI.bat -Chi ung-dung,driver  chi chay cac buoc nay
rem   CHAY_LAI.bat -LamLai               lam lai tu dau
rem   CHAY_LAI.bat -ChayThu              chi xem se lam gi
net session >nul 2>&1
if not errorlevel 1 goto chay
if "%~1"=="" goto nangquyen
powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
exit /b
:nangquyen
powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b
:chay
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SauCai.ps1" %*
