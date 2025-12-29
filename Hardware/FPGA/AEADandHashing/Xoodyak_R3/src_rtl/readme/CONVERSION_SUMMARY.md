# Xoodyak_R3 Pure Verilog (.v) Conversion Summary
## Using Separate Function Modules (Option B)

## Files to Convert (Without LWC Components)

### ✅ Core Files to Convert:

1. **Foundation (Types, Constants, Functions):**
   - `xoodoo_types.vh` → Create new (optional `define macros for widths)
   - `xoodoo_globals.vhd` → `xoodoo_globals_func.v` (utility module with functions)
   - `design_params.vh` → Create new (`define constants) or use module parameters
   - `design_pkg.vhd` → `design_funcs.v` (utility module with functions)

2. **Xoodoo Core Components:**
   - `xoodoo_rc.vhd` → `xoodoo_rc.sv`
   - `xoodoo_round.vhd` → `xoodoo_round.sv`
   - `xoodoo_register.vhd` → `xoodoo_register.sv`
   - `xoodoo_n_rounds.vhd` → `xoodoo_n_rounds.sv`
   - `xoodoo.vhd` → `xoodoo.sv`

3. **Top-Level:**
   - `CryptoCore.vhd` → `CryptoCore.sv`

### ❌ Files EXCLUDED (LWC Directory):
- `LWC/NIST_LWAPI_pkg.vhd` - Only header constants needed, will be in design_pkg.sv
- `LWC/StepDownCountLd.vhd`
- `LWC/key_piso.vhd`
- `LWC/data_piso.vhd`
- `LWC/PreProcessor.vhd`
- `LWC/data_sipo.vhd`
- `LWC/PostProcessor.vhd`
- `LWC/fwft_fifo.vhd`
- `LWC/LWC.vhd`

## Final Pure Verilog (.v) File Structure

```
src_rtl/
├── xoodoo_types.vh            (optional: `define macros for bit widths)
├── design_params.vh           (optional: `define constants, or use module parameters)
├── xoodoo_globals_func.v      (utility module with state conversion functions)
├── design_funcs.v             (utility module with design_pkg functions)
├── xoodoo_rc.v                (round constant generator)
├── xoodoo_round.v             (single Xoodoo round)
├── xoodoo_register.v          (state register)
├── xoodoo_n_rounds.v          (multiple rounds per cycle)
├── xoodoo.v                   (top-level Xoodoo permutation)
└── CryptoCore.v               (main Xoodyak crypto core)
```

**Total: 9-10 Verilog files** (8 modules + 1-2 optional header files)
- 2 optional header files (.vh) for constants/macros
- 2 utility modules for functions
- 5 Xoodoo core modules
- 1 top-level module (CryptoCore)

## Conversion Order (Pure Verilog)

1. **Phase 1:** Foundation
   - Create `xoodoo_types.vh` (optional)
   - Create `design_params.vh` or use module parameters
   - `xoodoo_globals.vhd` → `xoodoo_globals_func.v` (utility module)
   - `design_pkg.vhd` → `design_funcs.v` (utility module)

2. **Phase 2:** Xoodoo Core (xoodoo_rc → xoodoo_round → xoodoo_register → xoodoo_n_rounds → xoodoo)
   - Complex due to 3D array flattening to 384-bit vectors
   - Manual bit indexing: `[128*y + 32*x + i]`

3. **Phase 3:** CryptoCore (top-level module)
   - Large FSM with manual type conversions
   - Functions inlined or from utility modules

## Estimated Timeline: 3-4 weeks (16-22 days)
- More time needed due to manual array handling and function module approach

## Key Approach: Separate Function Modules

- **No packages** - Use utility modules for shared functions
- **No typedefs** - Use raw bit vectors `[383:0]` for state
- **Functions** - In separate utility modules (`xoodoo_globals_func.v`, `design_funcs.v`)
- **Constants** - `define in header files or parameters in modules
- **3D Arrays** - Flattened to 384-bit vectors with manual indexing

See `VERILOG_PURE_CONVERSION_PLAN.md` for detailed pure Verilog conversion strategy and `CONVERSION_CHECKLIST.md` for progress tracking.

