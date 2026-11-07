@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0CleanEmptyFolders.ps1" %*
