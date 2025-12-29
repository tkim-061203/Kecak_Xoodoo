# Xoodyak_R3 VHDL to Pure Verilog (.v) Conversion Checklist
## Using Separate Function Modules (Option B)

## Quick Reference - Conversion Status

### Phase 1: Foundation (Types, Constants, Functions)
- [ ] Create `xoodoo_types.vh` (optional `define macros)
- [ ] Create `design_params.vh` (`define constants) or use module parameters
- [ ] `xoodoo_globals.vhd` → `xoodoo_globals_func.v` (utility module)
- [ ] `design_pkg.vhd` → `design_funcs.v` (utility module)

### Phase 2: Xoodoo Core Components (Pure Verilog .v)
- [ ] `xoodoo_rc.vhd` → `xoodoo_rc.v` ⭐ Low complexity
- [ ] `xoodoo_round.vhd` → `xoodoo_round.v` ⭐⭐⭐ High complexity (3D array flattening)
- [ ] `xoodoo_register.vhd` → `xoodoo_register.v` ⭐⭐ Medium complexity
- [ ] `xoodoo_n_rounds.vhd` → `xoodoo_n_rounds.v` ⭐⭐⭐ High complexity
- [ ] `xoodoo.vhd` → `xoodoo.v` ⭐⭐ Medium complexity

### Phase 3: Top-Level Module (Pure Verilog .v)
- [ ] `CryptoCore.vhd` → `CryptoCore.v` ⭐⭐⭐⭐ Very High complexity

**Note:** LWC Interface Components are EXCLUDED from conversion (not converting LWC directory)
- [ ] `CryptoCore.vhd` → `CryptoCore.sv` ⭐⭐⭐⭐ Very High complexity

## Key Conversion Patterns Quick Reference

### Common Patterns
| VHDL | Pure Verilog (.v) |
|------|------------------|
| `std_logic` | `wire` or `reg` |
| `std_logic_vector(N downto 0)` | `wire [N:0]` or `reg [N:0]` |
| `integer range A to B` | `reg [$clog2(B+1)-1:0]` or `wire [...]` |
| `generic(...)` | `parameter` |
| `process(clk)` | `always @(posedge clk)` |
| `for x in 0 to 3 generate` | `generate for (genvar x = 0; x < 4; x = x + 1) begin : gen_label` |
| `(x-1) mod 4` | `((x-1) % 4)` or `((x-1+4) & 3)` |
| `rising_edge(clk)` | `@(posedge clk)` |
| `package` | Utility module or `include file |
| `function` in package | Function in utility module or inline |

### Type Definitions (Pure Verilog)
| VHDL | Pure Verilog (.v) |
|------|------------------|
| `type x_plane_type is array (0 to 3) of std_logic_vector(31 downto 0);` | Use raw `[127:0]` (4×32 bits) |
| `type x_state_type is array (0 to 2) of x_plane_type;` | Use raw `[383:0]` (384 bits) |
| Access: `state(y)(x)(i)` | Access: `state[128*y + 32*x + i]` |

## File Dependencies Graph

```
Foundation:
  xoodoo_globals.sv (no dependencies)
  design_pkg.sv (no dependencies, may use xoodoo_globals)
  nist_lwapi_pkg.sv (no dependencies)

Xoodoo Core:
  xoodoo_rc.sv (no dependencies)
  xoodoo_round.sv → xoodoo_globals.sv
  xoodoo_register.sv → xoodoo_globals.sv
  xoodoo_n_rounds.sv → xoodoo_round.sv, xoodoo_rc.sv, xoodoo_globals.sv
  xoodoo.sv → xoodoo_n_rounds.sv, xoodoo_register.sv, xoodoo_globals.sv

Top-Level:
  CryptoCore.sv → xoodoo.sv, design_pkg.sv, xoodoo_globals.sv

Note: LWC Interface components are excluded
```

## Critical Conversion Points

### ⚠️ Watch Out For:

1. **Array Indexing Direction**
   - VHDL: `(0 to N-1)` vs Verilog: `[0:N-1]` or `[N-1:0]`
   - Ensure bit ordering is consistent

2. **Modulo Operations**
   - `(x-1) mod 4` → Use `((x-1+4) & 3)` for power-of-2
   - `(i-5) mod 32` → Use `((i-5+32) & 31)` or `%` operator

3. **3D Array Access**
   - VHDL: `state(y)(x)(i)`
   - SystemVerilog: `state[y][x][i]` (with typedef)

4. **Integer Ranges**
   - `integer range 0 to 11` → `logic [3:0]` (4 bits for 0-15)

5. **Generate Loops with Conditions**
   - VHDL: `if I > 0 generate` → SystemVerilog: `if (i > 0) begin ... end`

6. **Package Imports**
   - VHDL: `use work.design_pkg.all;`
   - SystemVerilog: `import design_pkg::*;`

## Testing Milestones

- [ ] Phase 1: All packages compile and can be imported
- [ ] Phase 2: Xoodoo permutation produces correct output for known test vectors
- [ ] Phase 3: CryptoCore matches VHDL version functionality
- [ ] Final: Test vectors pass for AEAD and hashing modes

## Estimated Timeline (Pure Verilog with Function Modules)

- **Phase 1 (Foundation):** 2-3 days (function modules + constants)
- **Phase 2 (Xoodoo Core):** 6-8 days (more complex due to array flattening)
- **Phase 3 (CryptoCore):** 8-11 days (large FSM + manual conversions)
- **Total:** 16-22 days (3-4 weeks)

## Notes

- Start with packages (foundation)
- Work bottom-up for Xoodoo core
- Test incrementally
- Keep VHDL and Verilog versions in sync during development
- Document any design decisions or workarounds

