@echo off
rem usage: tb\uvm\sim.bat <program-name> [fast|rand|slow]     e.g.  tb\uvm\sim.bat t_basic rand
set TIMING=%2
if "%TIMING%"=="" set TIMING=rand
call xsim rv_sim -R -log xsim_%1.log -testplusarg prog=programs/%1 -testplusarg timing=%TIMING%
findstr /C:"TEST PASSED" /C:"UVM_ERROR" /C:"UVM_FATAL" xsim_%1.log
