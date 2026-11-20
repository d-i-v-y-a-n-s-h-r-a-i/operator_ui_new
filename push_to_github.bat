@echo off
title Push to GitHub
cd /d "%~dp0"
set PATH=C:\Users\anjal\AppData\Local\Programs\Git\cmd;%LOCALAPPDATA%\Programs\Git\cmd;%PATH%
echo ======================================================================
echo Pushing TANDAV repository to https://github.com/d-i-v-y-a-n-s-h-r-a-i/operator_ui_new.git
echo ======================================================================
git status
echo.
git add -A
git commit -m "Update TANDAV GCS: LoRa serial telemetry, mission maps, and cluster enhancements"
git push -u origin main
if %ERRORLEVEL% EQU 0 (
    echo.
    echo ==========================================
    echo Push succeeded successfully!
    echo ==========================================
) else (
    echo.
    echo Push failed or requires authentication.
)
pause
