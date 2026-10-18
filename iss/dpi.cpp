// DPI-C wrapper: lets SystemVerilog drive the C++ ISS one instruction at a time.
#include <cstdio>
#include <cstdlib>
#include "iss.h"

static ISS* g_iss = nullptr;

extern "C" void iss_load(const char* path) {
  if (!g_iss) g_iss = new ISS();
  g_iss->reset();
  if (!g_iss->load_bin(path)) {
    fprintf(stderr, "iss_load: cannot load %s\n", path);
    exit(1);
  }
}

// returns 1 and fills the retire record, or 0 if the ISS has already halted
extern "C" int iss_step(unsigned long long* order, unsigned long long* pc, unsigned int* insn,
                        unsigned int* rd, unsigned long long* rd_wdata, unsigned long long* pc_wdata,
                        unsigned long long* mem_addr, unsigned int* rmask, unsigned int* wmask,
                        unsigned long long* mem_rdata, unsigned long long* mem_wdata) {
  Retire r;
  if (!g_iss || !g_iss->step(r)) return 0;
  *order = r.order;         *pc = r.pc_rdata;       *insn = r.insn;
  *rd = r.rd_addr;          *rd_wdata = r.rd_wdata; *pc_wdata = r.pc_wdata;
  *mem_addr = r.mem_addr;   *rmask = r.mem_rmask;   *wmask = r.mem_wmask;
  *mem_rdata = r.mem_rdata; *mem_wdata = r.mem_wdata;
  return 1;
}
