@echo off
title TANDAV
cd /d "%~dp0"
where py >nul 2>nul
if %ERRORLEVEL% equ 0 (
    start "" py launch_qml.py
) else (
    where python >nul 2>nul
    if %ERRORLEVEL% equ 0 (
        start "" python launch_qml.py
    ) else (
        start "" "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" launch_qml.py
    )
)

