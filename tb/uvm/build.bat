@echo off
rem a rebuild throws away old coverage results (the coverage model may have changed)
if exist covdb rmdir /s /q covdb
set DEF=
if defined NODPI set DEF=-d NO_DPI
call xvlog rtl\regfile.v rtl\alu.v rtl\decode.v rtl\bpred.v rtl\icache.v rtl\core.v
if errorlevel 1 exit /b 1
call xvlog -sv -L uvm %DEF% tb\uvm\rv_if.sv tb\uvm\rv_pkg.sv tb\uvm\tb_uvm_top.sv
if errorlevel 1 exit /b 1
if defined NODPI goto nodpi
call xsc iss\iss.cpp iss\dpi.cpp
if errorlevel 1 exit /b 1
call xelab -timescale 1ns/1ps -L uvm -debug typical work.tb_uvm_top -s rv_sim -sv_lib dpi
if errorlevel 1 exit /b 1
set MGW=%XILINX_VIVADO%\tps\mingw\6.2.0\win64.o\nt\bin
for %%d in (libstdc++-6.dll libgcc_s_seh-1.dll libwinpthread-1.dll) do copy /y "%MGW%\%%d" xsim.dir\rv_sim\ >nul
exit /b 0
:nodpi
call xelab -timescale 1ns/1ps -L uvm -debug typical work.tb_uvm_top -s rv_sim
exit /b %errorlevel%