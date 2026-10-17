.RECIPEPREFIX = >
BUILD = ../../build/obj_core
RTL = $(wildcard ../../rtl/*.v)

$(BUILD)/sim_core: tb_core.sv $(RTL)
> verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD --top-module tb_core --Mdir $(BUILD) -o sim_core $(RTL) tb_core.sv

clean:
> rm -rf $(BUILD)
