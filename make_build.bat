@echo off
dmd -version=Unicode -version=WindowsXP build.d pipes.d dmd_win32.lib
