@echo off
rem usage: tb\uvm\regress.bat [fast|rand|slow]    runs every program in programs\, then merges coverage
set T=%1
if "%T%"=="" set T=rand
for %%f in (programs\*.hex) do call :one %%~nf
call tb\uvm\cov_report.bat
exit /b 0
:one
call tb\uvm\sim.bat %1 %T% > nul 2>&1
findstr /C:"TEST PASSED" xsim_%1.log > nul
if errorlevel 1 (echo FAIL %1) else (echo PASS %1)
exit /b 0
