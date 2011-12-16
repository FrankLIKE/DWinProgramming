@echo off
setlocal EnableDelayedExpansion
set "files="
for %%i in (*.d;*.di) do set files=!files! %%i
gdmd -ignore -lib -of..\gdc_win32.lib -I..\ -version=Unicode -version=WindowsXP %files% 
