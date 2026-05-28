@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo.
echo  WinLockTool installer
echo  by jayy ^| discord.gg/lumin
echo.

echo Adding WinLockTool to your user PATH...
set "TOOL_DIR=%~dp0bin"
for /f "tokens=2*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul') do set "USER_PATH=%%B"
echo ;%USER_PATH%; | find /I ";%TOOL_DIR%;" >nul
if errorlevel 1 (
  if defined USER_PATH (setx PATH "%USER_PATH%;%TOOL_DIR%" >nul) else (setx PATH "%TOOL_DIR%" >nul)
  echo Added %TOOL_DIR%. Open a new terminal to use winlock.
) else (
  echo %TOOL_DIR% is already on PATH.
)

echo.
echo Optional: install Sysinternals handle.exe for deeper scans
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bin\winlock.ps1" handles --install

echo.
echo Try:
echo   winlock dist
echo   winlock dist preview
echo.
endlocal
