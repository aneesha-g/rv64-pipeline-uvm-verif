.RECIPEPREFIX = >
PREFIX ?= riscv64-elf-
BUILD = ../build/sw
TESTS = $(patsubst tests/%.S,$(BUILD)/%.bin,$(wildcard tests/*.S))

all: $(TESTS)

$(BUILD)/%.elf: tests/%.S link.ld
> mkdir -p $(BUILD)
> $(PREFIX)gcc -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -static -T link.ld $< -o $@

$(BUILD)/%.bin: $(BUILD)/%.elf
> $(PREFIX)objcopy -O binary $< $@

.SECONDARY:
clean:
> rm -rf $(BUILD)
