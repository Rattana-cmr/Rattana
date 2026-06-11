@echo off
title ICT SMC EA — AI Signal Bridge
color 0A
cls

echo ============================================================
echo   ICT SMC EA — AI Signal Bridge Launcher
echo   For use with ICT_SMC_EA_V1.6
echo ============================================================
echo.

:: ── Check Python is installed ────────────────────────────────
python --version >nul 2>&1
if %errorlevel% neq 0 (
    color 0C
    echo   [ERROR] Python is NOT installed on this computer.
    echo.
    echo   HOW TO INSTALL PYTHON (free, one time only):
    echo   1. Open your browser
    echo   2. Go to:  https://www.python.org/downloads/
    echo   3. Click the big yellow "Download Python" button
    echo   4. Run the installer
    echo   5. IMPORTANT: tick "Add Python to PATH" at the bottom
    echo      of the first installer screen
    echo   6. Click Install Now
    echo   7. After install finishes, double-click this file again
    echo.
    echo   Press any key to open the Python download page...
    pause >nul
    start https://www.python.org/downloads/
    exit /b
)

:: ── Show Python version found ─────────────────────────────────
for /f "tokens=*" %%i in ('python --version 2^>^&1') do set PYVER=%%i
echo   Found: %PYVER%
echo.

:: ── Check the script exists in the same folder ───────────────
if not exist "%~dp0ai_signal_bridge.py" (
    color 0C
    echo   [ERROR] ai_signal_bridge.py not found next to this file.
    echo   Make sure run_ai_bridge.bat and ai_signal_bridge.py
    echo   are in the same folder.
    echo.
    pause
    exit /b
)



:: ── All good — launch the bridge ─────────────────────────────
color 0A
echo   [OK] Starting AI Signal Bridge...
echo   Keep this window open while MT5 is running.
echo   Close this window (or press Ctrl+C) to stop.
echo.
echo ============================================================
echo.

python "%~dp0ai_signal_bridge.py"

:: ── If script exits unexpectedly, keep window open ───────────
echo.
echo ============================================================
echo   Bridge stopped. Press any key to close this window.
pause >nul
