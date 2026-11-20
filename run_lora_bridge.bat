@echo off
title TANDAV LoRa Serial Bridge
cd /d "%~dp0"
echo ====================================================
echo Starting TANDAV LoRa Serial Bridge on COM3 @ 115200
echo ====================================================
echo NOTE: Ensure Arduino IDE Serial Monitor is CLOSED!
echo.
where py >nul 2>nul
if %ERRORLEVEL% equ 0 (
    py backend\lora_serial.py --port COM3 --baud 115200
) else (
    where python >nul 2>nul
    if %ERRORLEVEL% equ 0 (
        python backend\lora_serial.py --port COM3 --baud 115200
    ) else (
        "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" backend\lora_serial.py --port COM3 --baud 115200
    )
)
pause
