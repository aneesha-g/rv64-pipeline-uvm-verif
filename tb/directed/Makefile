.RECIPEPREFIX = >
BUILD   = ../../build/obj_core
BUILD_N = ../../build/obj_core_nobp
RTL     = $(wildcard ../../rtl/*.v)
VFLAGS  = --binary --timing --trace -Wno-fatal -Wno-PINMISSING -Wno-WIDTH -Wno-TIMESCALEMOD --top-module tb_core

all: $(BUILD)/sim_core $(BUILD_N)/sim_core_nobp

$(BUILD)/sim_core: tb_core.sv $(RTL)
> verilator $(VFLAGS) --Mdir $(BUILD) -o sim_core $(RTL) tb_core.sv

$(BUILD_N)/sim_core_nobp: tb_core.sv $(RTL)
> verilator $(VFLAGS) -GBP_EN=0 --Mdir $(BUILD_N) -o sim_core_nobp $(RTL) tb_core.sv

clean:
> rm -rf $(BUILD) $(BUILD_N)
