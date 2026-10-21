@echo off
rem usage: tb\uvm\sim.bat <program-name> [fast|rand|slow]     e.g.  tb\uvm\sim.bat t_basic rand
rem each run also saves its functional coverage in covdb\xsim.covdb\<program>_<timing>
set TIMING=%2
if "%TIMING%"=="" set TIMING=rand
if not exist covdb mkdir covdb
if exist xsim_%1.log del xsim_%1.log
rem the options go through a file: Vivado's launcher script splits "name=value" arguments at the "="
> xsim_args.txt echo -R -log xsim_%1.log -cov_db_dir covdb -cov_db_name %1_%TIMING% -testplusarg prog=programs/%1 -testplusarg timing=%TIMING%
call xsim rv_sim -f xsim_args.txt
findstr /C:"TEST PASSED" /C:"FUNC COVERAGE" /C:"UVM_ERROR" /C:"UVM_FATAL" xsim_%1.log
