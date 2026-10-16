#pragma once
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

#ifndef XLEN
#define XLEN 32
#endif

#if XLEN == 32
using xlen_t  = uint32_t;
using sxlen_t = int32_t;
#else
using xlen_t  = uint64_t;
using sxlen_t = int64_t;
#endif

constexpr xlen_t MEM_BASE = 0x80000000u;
constexpr size_t MEM_SIZE = 1u << 20;  // 1 MiB

// One retired instruction (RVFI-style)
struct Retire {
  uint64_t order;
  xlen_t   pc_rdata;   // pc of this instruction
  uint32_t insn;
  uint8_t  rd_addr;    // 0 if nothing written (or rd == x0)
  xlen_t   rd_wdata;
  xlen_t   pc_wdata;   // next pc
  xlen_t   mem_addr;   // effective address
  uint8_t  mem_rmask;  // bytes read (0x1, 0x3, 0xF)
  uint8_t  mem_wmask;  // bytes written
  xlen_t   mem_rdata;  // raw loaded value
  xlen_t   mem_wdata;  // raw stored value
  bool     trap;
};

class ISS {
 public:
  ISS();
  void reset();
  bool load_bin(const std::string& path);
  bool step(Retire& r);          // false once halted
  bool halted() const { return halted_; }
  xlen_t reg(int i) const { return x_[i]; }
  void dump_regs(FILE* f) const;

 private:
  bool   in_range(xlen_t a, int size) const;
  xlen_t rd_mem(xlen_t a, int size) const;
  void   wr_mem(xlen_t a, int size, xlen_t v);

  xlen_t x_[32];
  xlen_t pc_;
  std::vector<uint8_t> mem_;
  bool halted_;
  uint64_t order_;
};

void print_retire(FILE* f, const Retire& r);
