.RECIPEPREFIX = >
XLEN ?= 32
CXXFLAGS = -std=c++17 -O2 -Wall -Wextra -DXLEN=$(XLEN)
BUILD = ../build
TARGET = $(BUILD)/iss_rv$(XLEN)

$(TARGET): iss.cpp main.cpp iss.h
> mkdir -p $(BUILD)
> $(CXX) $(CXXFLAGS) iss.cpp main.cpp -o $@

clean:
> rm -rf $(BUILD)
