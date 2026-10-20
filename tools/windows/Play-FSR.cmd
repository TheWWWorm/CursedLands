@echo off
cd /d "%~dp0"
start "" "%~dp0CursedLands.exe" --rendering-method forward_plus --rendering-driver d3d12 --render-thread safe -- --experimental-fsr
