@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0winlock.ps1" dist free %*
