.RECIPEPREFIX = >
BUILD   = ../../build/obj_core
BUILD_N = ../../build/obj_core_nobp
RTL     = $(wildcard ../../rtl/*.v)
ISS_SRC = ../../iss/iss.cpp ../../iss/dpi.cpp
TB_SRC  = rvfi_checker.sv tb_core.sv
VFLAGS  = --binary --timing --trace -Wno-fatal -Wno-PINMISSING -Wno-WIDTH -Wno-TIMESCALEMOD --top-module tb_core --CFLAGS -DXLEN=32

all: $(BUILD)/sim_core $(BUILD_N)/sim_core_nobp

$(BUILD)/sim_core: $(TB_SRC) $(RTL) $(ISS_SRC) ../../iss/iss.h
> verilator $(VFLAGS) --Mdir $(BUILD) -o sim_core $(RTL) $(TB_SRC) $(ISS_SRC)

$(BUILD_N)/sim_core_nobp: $(TB_SRC) $(RTL) $(ISS_SRC) ../../iss/iss.h
> verilator $(VFLAGS) -GBP_EN=0 --Mdir $(BUILD_N) -o sim_core_nobp $(RTL) $(TB_SRC) $(ISS_SRC)

clean:
> rm -rf $(BUILD) $(BUILD_N)
