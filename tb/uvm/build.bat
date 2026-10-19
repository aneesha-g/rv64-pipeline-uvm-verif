@echo off
rem usage (from the repo root, after settings64.bat):   tb\uvm\build.bat
rem set NODPI=1 first to build WITHOUT the C++ ISS (milestone 1); "set NODPI=" to turn it back on
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
exit /b %errorlevel%
:nodpi
call xelab -timescale 1ns/1ps -L uvm -debug typical work.tb_uvm_top -s rv_sim
exit /b %errorlevel%
