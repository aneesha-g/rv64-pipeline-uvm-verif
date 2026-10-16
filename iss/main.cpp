#include <cstdlib>
#include "iss.h"

int main(int argc, char** argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s prog.bin [max_insns]\n", argv[0]);
    return 1;
  }
  ISS cpu;
  if (!cpu.load_bin(argv[1])) {
    fprintf(stderr, "cannot load %s\n", argv[1]);
    return 1;
  }
  uint64_t max = (argc > 2) ? strtoull(argv[2], nullptr, 0) : 1000000;
  Retire r;
  uint64_t n = 0;
  while (n < max && cpu.step(r)) {
    print_retire(stdout, r);
    n++;
  }
  fprintf(stderr, "halted after %llu instructions%s\n", (unsigned long long)n,
          r.trap ? " (TRAP)" : "");
  cpu.dump_regs(stderr);
  return 0;
}
