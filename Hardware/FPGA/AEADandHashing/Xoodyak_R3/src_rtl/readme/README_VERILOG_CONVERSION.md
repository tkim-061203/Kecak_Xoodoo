# Xoodyak_R3 VHDL to Pure Verilog Conversion

## Overview

This directory contains the conversion plan for converting Xoodyak_R3 from VHDL to **Pure Verilog (.v)** using **Separate Function Modules (Option B)**.

## Conversion Approach

- **Language:** Pure Verilog (.v) - NOT SystemVerilog
- **Function Organization:** Separate utility modules (Option B)
- **Type System:** Raw bit vectors (no typedefs)
- **Constants:** `define macros or module parameters
- **3D Arrays:** Flattened to 384-bit vectors with manual indexing

## Key Documents

1. **VERILOG_PURE_CONVERSION_PLAN.md** - Detailed conversion plan for pure Verilog
2. **CONVERSION_SUMMARY.md** - Quick summary of files and structure
3. **CONVERSION_CHECKLIST.md** - Progress tracking checklist
4. **VERILOG_VS_SYSTEMVERILOG.md** - Comparison of .v vs .sv approaches

## Files to Convert

**Total: 9-10 files** (8 modules + 1-2 optional headers)

### Foundation:
- `xoodoo_types.vh` (optional)
- `design_params.vh` (optional) 
- `xoodoo_globals_func.v` (utility module)
- `design_funcs.v` (utility module)

### Xoodoo Core:
- `xoodoo_rc.v`
- `xoodoo_round.v`
- `xoodoo_register.v`
- `xoodoo_n_rounds.v`
- `xoodoo.v`

### Top-Level:
- `CryptoCore.v`

## Excluded Files

All LWC directory components are excluded:
- `LWC/NIST_LWAPI_pkg.vhd` (only constants needed, will be in design_params.vh)
- `LWC/PreProcessor.vhd`
- `LWC/PostProcessor.vhd`
- `LWC/LWC.vhd`
- Other LWC support files

## Key Challenges

1. **3D Array Flattening:** Must manually calculate indices `[128*y + 32*x + i]`
2. **Function Sharing:** Functions in utility modules (not easily shareable)
3. **Type Conversions:** Manual bit manipulation
4. **More Verbose Code:** Due to explicit indexing

## Timeline

Estimated: **16-22 days** (3-4 weeks)

## Getting Started

1. Review `VERILOG_PURE_CONVERSION_PLAN.md` for detailed strategy
2. Use `CONVERSION_CHECKLIST.md` to track progress
3. Start with Phase 1 (Foundation) - types, constants, function modules
4. Then proceed bottom-up through Xoodoo core components
5. Finish with CryptoCore (top-level)

## Notes

- Functions will be in separate utility modules (`xoodoo_globals_func.v`, `design_funcs.v`)
- Complex functions may need to be inlined in modules for synthesis
- 3D array access requires careful bit indexing verification
- Test each module incrementally to ensure correctness

