#include "iss.h"
#include <algorithm>
#include <cstring>
#include <fstream>

static constexpr int W = XLEN / 4;  // hex digits per register

ISS::ISS() : mem_(MEM_SIZE) { reset(); }

void ISS::reset() {
  memset(x_, 0, sizeof x_);
  std::fill(mem_.begin(), mem_.end(), 0);
  pc_ = MEM_BASE;
  halted_ = false;
  order_ = 0;
}

bool ISS::load_bin(const std::string& path) {
  std::ifstream f(path, std::ios::binary);
  if (!f) return false;
  f.read(reinterpret_cast<char*>(mem_.data()), MEM_SIZE);
  return f.gcount() > 0;
}

bool ISS::in_range(xlen_t a, int size) const {
  return a >= MEM_BASE && (uint64_t)(a - MEM_BASE) + size <= MEM_SIZE;
}

xlen_t ISS::rd_mem(xlen_t a, int size) const {
  xlen_t v = 0;
  for (int i = 0; i < size; i++) v |= (xlen_t)mem_[a - MEM_BASE + i] << (8 * i);
  return v;
}

void ISS::wr_mem(xlen_t a, int size, xlen_t v) {
  for (int i = 0; i < size; i++) mem_[a - MEM_BASE + i] = (v >> (8 * i)) & 0xff;
}

bool ISS::step(Retire& r) {
  if (halted_) return false;
  memset(&r, 0, sizeof r);
  r.order = order_++;
  r.pc_rdata = pc_;

  if ((pc_ & 3) || !in_range(pc_, 4)) {  // bad fetch
    halted_ = true; r.trap = true; r.pc_wdata = pc_;
    return true;
  }

  uint32_t insn = (uint32_t)rd_mem(pc_, 4);
  r.insn = insn;

  uint32_t opcode = insn & 0x7f;
  uint32_t rd  = (insn >> 7)  & 31;
  uint32_t f3  = (insn >> 12) & 7;
  uint32_t rs1 = (insn >> 15) & 31;
  uint32_t rs2 = (insn >> 20) & 31;
  uint32_t f7  = insn >> 25;
  bool alt = (insn >> 30) & 1;  // SUB / SRA / SRAI

  int32_t imm_i = (int32_t)insn >> 20;
  int32_t imm_s = (int32_t)(((int32_t)(insn & 0xfe000000) >> 20) | ((insn >> 7) & 0x1f));
  int32_t imm_b = (int32_t)(((int32_t)(insn & 0x80000000) >> 19) | ((insn & 0x80) << 4) |
                            ((insn >> 20) & 0x7e0) | ((insn >> 7) & 0x1e));
  int32_t imm_u = (int32_t)(insn & 0xfffff000);
  int32_t imm_j = (int32_t)(((int32_t)(insn & 0x80000000) >> 11) | (insn & 0xff000) |
                            ((insn >> 9) & 0x800) | ((insn >> 20) & 0x7fe));

  xlen_t a = x_[rs1], b = x_[rs2];
  xlen_t next = pc_ + 4, wb = 0;
  bool wen = false, illegal = false;
  const int shmask = XLEN - 1;

  switch (opcode) {
    case 0x37:  // LUI
      wb = (xlen_t)(sxlen_t)imm_u; wen = true; break;
    case 0x17:  // AUIPC
      wb = pc_ + (xlen_t)(sxlen_t)imm_u; wen = true; break;
    case 0x6f:  // JAL
      wb = pc_ + 4; next = pc_ + (xlen_t)(sxlen_t)imm_j; wen = true; break;
    case 0x67:  // JALR
      if (f3 != 0) { illegal = true; break; }
      wb = pc_ + 4; next = (a + (xlen_t)(sxlen_t)imm_i) & ~(xlen_t)1; wen = true; break;
    case 0x63: {  // branches
      bool t = false;
      switch (f3) {
        case 0: t = (a == b); break;
        case 1: t = (a != b); break;
        case 4: t = ((sxlen_t)a <  (sxlen_t)b); break;
        case 5: t = ((sxlen_t)a >= (sxlen_t)b); break;
        case 6: t = (a <  b); break;
        case 7: t = (a >= b); break;
        default: illegal = true;
      }
      if (t) next = pc_ + (xlen_t)(sxlen_t)imm_b;
      break;
    }
    case 0x03: {  // loads
      int size = 0; bool sgn = false;
      switch (f3) {
        case 0: size = 1; sgn = true;  break;  // LB
        case 1: size = 2; sgn = true;  break;  // LH
        case 2: size = 4; sgn = true;  break;  // LW
        case 4: size = 1; sgn = false; break;  // LBU
        case 5: size = 2; sgn = false; break;  // LHU
        default: illegal = true;
      }
      if (illegal) break;
      xlen_t ea = a + (xlen_t)(sxlen_t)imm_i;
      if (!in_range(ea, size)) { illegal = true; break; }
      xlen_t v = rd_mem(ea, size);
      r.mem_addr = ea; r.mem_rmask = (1u << size) - 1; r.mem_rdata = v;
      if (sgn) {
        if (size == 1) v = (xlen_t)(sxlen_t)(int8_t)v;
        else if (size == 2) v = (xlen_t)(sxlen_t)(int16_t)v;
        else v = (xlen_t)(sxlen_t)(int32_t)v;
      }
      wb = v; wen = true;
      break;
    }
    case 0x23: {  // stores
      int size = (f3 == 0) ? 1 : (f3 == 1) ? 2 : (f3 == 2) ? 4 : 0;
      if (!size) { illegal = true; break; }
      xlen_t ea = a + (xlen_t)(sxlen_t)imm_s;
      if (!in_range(ea, size)) { illegal = true; break; }
      xlen_t m = (size * 8 >= XLEN) ? ~(xlen_t)0 : (((xlen_t)1 << (size * 8)) - 1);
      wr_mem(ea, size, b & m);
      r.mem_addr = ea; r.mem_wmask = (1u << size) - 1; r.mem_wdata = b & m;
      break;
    }
    case 0x13: {  // OP-IMM
      xlen_t imm = (xlen_t)(sxlen_t)imm_i;
      uint32_t sh = (insn >> 20) & shmask;
      switch (f3) {
        case 0: wb = a + imm; break;
        case 1: wb = a << sh; break;
        case 2: wb = ((sxlen_t)a < (sxlen_t)imm); break;
        case 3: wb = (a < imm); break;
        case 4: wb = a ^ imm; break;
        case 5: wb = alt ? (xlen_t)((sxlen_t)a >> sh) : (a >> sh); break;
        case 6: wb = a | imm; break;
        case 7: wb = a & imm; break;
      }
      wen = true;
      break;
    }
    case 0x33: {  // OP
      if (f7 != 0 && !(f7 == 0x20 && (f3 == 0 || f3 == 5))) { illegal = true; break; }
      uint32_t sh = b & shmask;
      switch (f3) {
        case 0: wb = alt ? a - b : a + b; break;
        case 1: wb = a << sh; break;
        case 2: wb = ((sxlen_t)a < (sxlen_t)b); break;
        case 3: wb = (a < b); break;
        case 4: wb = a ^ b; break;
        case 5: wb = alt ? (xlen_t)((sxlen_t)a >> sh) : (a >> sh); break;
        case 6: wb = a | b; break;
        case 7: wb = a & b; break;
      }
      wen = true;
      break;
    }
    case 0x0f:  // FENCE = nop
      break;
    case 0x73:  // ECALL / EBREAK = end of test
      if (insn == 0x00000073 || insn == 0x00100073) halted_ = true;
      else illegal = true;
      break;
    default:
      illegal = true;
  }

  if (illegal) {
    halted_ = true; r.trap = true; r.pc_wdata = pc_;
    return true;
  }
  if (wen && rd != 0) { x_[rd] = wb; r.rd_addr = rd; r.rd_wdata = wb; }
  r.pc_wdata = next;
  pc_ = next;
  return true;
}

void ISS::dump_regs(FILE* f) const {
  for (int i = 0; i < 32; i++)
    fprintf(f, "x%-2d=%0*llx%s", i, W, (unsigned long long)x_[i], (i % 4 == 3) ? "\n" : "  ");
}

// order pc insn rd rd_wdata pc_wdata mem_addr rmask wmask mem_rdata mem_wdata
void print_retire(FILE* f, const Retire& r) {
  fprintf(f, "%llu %0*llx %08x %02x %0*llx %0*llx %0*llx %x %x %0*llx %0*llx\n",
          (unsigned long long)r.order, W, (unsigned long long)r.pc_rdata, r.insn, r.rd_addr,
          W, (unsigned long long)r.rd_wdata, W, (unsigned long long)r.pc_wdata,
          W, (unsigned long long)r.mem_addr, r.mem_rmask, r.mem_wmask,
          W, (unsigned long long)r.mem_rdata, W, (unsigned long long)r.mem_wdata);
}
