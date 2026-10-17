@echo off
cd /d "%~dp0"
start "" "%~dp0CursedLands.exe" --rendering-method gl_compatibility --rendering-driver opengl3 --render-thread safe -- --compatibility-recovery
