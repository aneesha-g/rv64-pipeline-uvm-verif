@echo off
rem usage: tb\uvm\cov_report.bat
rem merges the coverage of every run saved under covdb\ and writes an HTML + text report to covreport\
setlocal enabledelayedexpansion
set ARGS=
for /d %%d in (covdb\xsim.covdb\*) do set ARGS=!ARGS! -cov_db_dir covdb -cov_db_name %%~nxd
if "!ARGS!"=="" (
  echo No coverage data yet. Run tb\uvm\regress.bat first.
  exit /b 1
)
if exist covreport rmdir /s /q covreport
if exist covmerge rmdir /s /q covmerge
call xcrg !ARGS! -merge_dir covmerge -merge_db_name all -report_dir covreport -report_format all > xcrg_run.log 2>&1
if errorlevel 1 (
  echo xcrg failed - see xcrg_run.log
  exit /b 1
)
echo.
echo Merged coverage report: covreport\dashboard.html
endlocal
exit /b 0
