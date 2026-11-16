@echo off
rem geom-Pet launcher: starts the pet with no console window left behind.
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0geom-Pet.ps1"
