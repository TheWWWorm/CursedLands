@echo off
cd /d "%~dp0"
start "" "%~dp0CursedLands.exe" --rendering-method forward_plus --rendering-driver vulkan --render-thread safe -- --vulkan-recovery
