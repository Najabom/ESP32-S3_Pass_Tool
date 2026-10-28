@echo off
REM PassDeck PC launcher (run from this directory or double-click).
REM Prefers the project's known-good interpreter (Python 3.14 + PySide6),
REM falls back to `python` on PATH.
cd /d "%~dp0"

set "APP_PY="
if exist "%LOCALAPPDATA%\Programs\Python\Python314\python.exe" set "APP_PY=%LOCALAPPDATA%\Programs\Python\Python314\python.exe"
if defined APP_PY (
    "%APP_PY%" -c "import PySide6, bleak" >nul 2>&1 || set "APP_PY="
)
if not defined APP_PY (
    python -c "import PySide6, bleak" >nul 2>&1 && set "APP_PY=python"
)
if not defined APP_PY (
    echo [ERROR] PySide6 / bleak not found. Run: python -m pip install -r requirements.txt
    pause
    exit /b 1
)
"%APP_PY%" app\app.py
if errorlevel 1 pause