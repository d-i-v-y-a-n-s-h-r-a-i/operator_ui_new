@echo off
title Push to GitHub
cd /d "%~dp0"
set PATH=C:\Users\Omkar\AppData\Local\Programs\@codebufffreebuff-desktop\resources\git\cmd;C:\Users\Omkar\AppData\Local\Programs\@codebufffreebuff-desktop\resources\git\ucrt64\bin;%PATH%
echo Pushing TANDAV repository to https://github.com/d-i-v-y-a-n-s-h-r-a-i/operator_ui_new.git ...
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
