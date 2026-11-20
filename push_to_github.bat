@echo off
setlocal enabledelayedexpansion
title Push Updates to GitHub - TANDAV GCS
cd /d "%~dp0"

echo ======================================================================
echo           TANDAV Autonomous Marine GCS - GitHub Auto-Updater
echo ======================================================================
echo Target Remote: https://github.com/d-i-v-y-a-n-s-h-r-a-i/operator_ui_new.git
echo.

:: Ensure Git is on PATH
set "PATH=%LOCALAPPDATA%\Programs\Git\cmd;%ProgramFiles%\Git\cmd;%LOCALAPPDATA%\Programs\Git\bin;%PATH%"

where git >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Git could not be found. Please ensure Git is installed.
    echo.
    pause
    exit /b 1
)

:: Ensure user identity is configured
git config user.name >nul 2>nul
if %ERRORLEVEL% neq 0 (
    git config user.name "divyanshrai"
    git config user.email "divyanshrai@users.noreply.github.com"
)

:: Ensure Git LFS is enabled
git lfs install >nul 2>nul

echo [1/3] Checking changed and newly added files...
git status --short
echo.

echo [2/3] Staging all files and changes...
git add -A

:: Check if there are uncommitted changes
git diff-index --quiet HEAD -- 2>nul
if %ERRORLEVEL% neq 0 (
    set "COMMIT_MSG=Update: %date% %time% - latest software and telemetry updates"
    echo Committing changes: "!COMMIT_MSG!"
    git commit -m "!COMMIT_MSG!"
) else (
    echo No new local changes to commit. Proceeding to push existing commits...
)
echo.

echo [3/3] Uploading and pushing to GitHub (origin main)...
echo.
git push -u origin main

if %ERRORLEVEL% equ 0 (
    echo.
    echo ======================================================================
    echo [SUCCESS] Everything has been uploaded and pushed to GitHub!
    echo ======================================================================
) else (
    echo.
    echo ======================================================================
    echo [NOTICE] Push requires GitHub login or permissions.
    echo If a browser window opened, complete your sign-in to finish pushing.
    echo ======================================================================
)

echo.
pause
