# Verilog Conversion Plan for Xoodyak_R3

## Overview
This document outlines the plan to convert the VHDL implementation of Xoodyak_R3 to Verilog **WITHOUT LWC components**. The conversion will maintain functional equivalence while adapting VHDL-specific constructs to Verilog equivalents.

**Scope:** Only core Xoodyak/Xoodoo components are converted. LWC directory components (PreProcessor, PostProcessor, LWC wrapper, etc.) are excluded. The NIST header constants needed by CryptoCore will be included directly in `design_pkg.sv`.

## Project Structure Analysis

### Current VHDL File Hierarchy (from source_list.txt):

#### **Packages (Foundation Layer)**
1. `design_pkg.vhd` - Design parameters, constants, and utility functions (will include NIST header constants directly)
2. `xoodoo_globals.vhd` - Xoodoo-specific types, functions, and constants
3. ~~`LWC/NIST_LWAPI_pkg.vhd`~~ - **EXCLUDED** (only header constants needed by CryptoCore, will be included in design_pkg.sv)

#### **Xoodoo Permutation Core (Low-Level Components)**
4. `xoodoo_rc.vhd` - Round constant generator
5. `xoodoo_round.vhd` - Single Xoodoo round (theta, rho-west, iota, chi, rho-east)
6. `xoodoo_n_rounds.vhd` - Multiple rounds per cycle (configurable)
7. `xoodoo_register.vhd` - State register with initialization and word access
8. `xoodoo.vhd` - Top-level Xoodoo permutation module

#### ~~**LWC Interface Components**~~ **EXCLUDED FROM CONVERSION**
~~9-16. LWC directory components~~ - Not converting per requirements. These are NIST API wrappers.

#### **Top-Level Module**
17. `CryptoCore.vhd` - Main Xoodyak crypto core implementation

---

## Conversion Strategy

### Phase 1: Package/Include Files (Foundation)

#### 1.1 Convert `xoodoo_globals.vhd` → `xoodoo_globals.vh` / `xoodoo_globals.sv`
**VHDL Features to Convert:**
- **Type definitions**: `x_plane_type`, `x_state_type` (3D arrays)
  - Verilog: Use `typedef struct` or `typedef logic [31:0]` arrays
- **Functions**: `xstate_to_stdlogicvector()`, `stdlogicvector_to_xstate()`
  - Verilog: Use functions or generate blocks
- **Constants**: `active_rst`, `ZERO_STATE`
  - Verilog: `parameter` or `localparam`

**Verilog Approach:**
```systemverilog
// Use SystemVerilog for better type support
typedef logic [31:0] x_word_t;
typedef x_word_t [0:3] x_plane_t;
typedef x_plane_t [0:2] x_state_t;

// Functions as SystemVerilog functions or Verilog tasks
function automatic logic [383:0] xstate_to_stdlogicvector(x_state_t state);
  // implementation
endfunction
```

#### 1.2 Convert `design_pkg.vhd` → `design_pkg.sv`
**VHDL Features to Convert:**
- **Constants**: `roundsPerCycle`, `TAG_SIZE`, `KEY_SIZE`, etc.
  - Verilog: `parameter` declarations
- **Functions**: `get_words()`, `log2_ceil()`, `reverse_byte()`, `reverse_bit()`, `padd()`, `max()`, `domain_word()`, `select_bytes()`
  - Verilog: SystemVerilog functions
- **NIST Header Constants**: Include header type constants from NIST_LWAPI_pkg that CryptoCore uses:
  - `HDR_AD`, `HDR_NPUB`, `HDR_PT`, `HDR_CT`, `HDR_TAG`, `HDR_HASH_VALUE`, `HDR_HASH_MSG`

**Verilog Approach:**
```systemverilog
package design_pkg;
  // Design parameters
  parameter int ROUNDS_PER_CYCLE = 3;
  parameter int TAG_SIZE = 128;
  parameter int KEY_SIZE = 128;
  // ... other constants
  
  // NIST Header Type Constants (from NIST_LWAPI_pkg)
  parameter logic [3:0] HDR_AD         = 4'b0001;
  parameter logic [3:0] HDR_NPUB       = 4'b1101;
  parameter logic [3:0] HDR_PT         = 4'b0100;
  parameter logic [3:0] HDR_CT         = 4'b0101;
  parameter logic [3:0] HDR_TAG        = 4'b1000;
  parameter logic [3:0] HDR_HASH_VALUE = 4'b1001;
  parameter logic [3:0] HDR_HASH_MSG   = 4'b0111;
  
  function automatic int get_words(int size, int iowidth);
    return (size % iowidth > 0) ? (size/iowidth + 1) : (size/iowidth);
  endfunction
  
  // ... other functions
endpackage
```

**Note:** NIST_LWAPI_pkg is not converted as a separate package. Only the header constants needed by CryptoCore are included in design_pkg.

---

### Phase 2: Xoodoo Core Components (Bottom-Up)

#### 2.1 Convert `xoodoo_rc.vhd` → `xoodoo_rc.sv`
**VHDL Features to Convert:**
- **Case statement** for round constant selection
- **Arithmetic operations** on state_in (5:0)
- **Combinational logic** process

**Complexity:** ⭐ Low - Mostly combinational logic

**Key Conversions:**
- VHDL `std_logic_vector` → Verilog `logic`
- VHDL `unsigned` arithmetic → Verilog arithmetic
- VHDL `case` → Verilog `case` (similar syntax)

#### 2.2 Convert `xoodoo_round.vhd` → `xoodoo_round.sv`
**VHDL Features to Convert:**
- **Multiple generate loops** for combinatorial operations
- **Modulo operations** for rotations/shifts: `(x-1) mod 4`, `(i-5) mod 32`, etc.
- **3D array indexing**: `state_type(y)(x)(i)`
- **Bitwise operations**: XOR, AND, NOT

**Complexity:** ⭐⭐ Medium - Complex array indexing and modulo operations

**Key Conversions:**
- Generate loops → `generate` blocks or `for` loops
- Modulo operations: Use `%` operator or pre-computed indices
- 3D arrays: Use SystemVerilog typedefs from `xoodoo_globals`

#### 2.3 Convert `xoodoo_register.vhd` → `xoodoo_register.sv`
**VHDL Features to Convert:**
- **Clocked process** with reset and enable logic
- **Conditional assignments** based on `init`, `running_in`, `start_in`
- **Integer range** parameter: `word_index_in : integer range 0 to 11`
- **Division/modulo** for array indexing: `word_index_in/4`, `word_index_in mod 4`

**Complexity:** ⭐⭐ Medium - Sequential logic with complex control

**Key Conversions:**
- VHDL process → `always_ff @(posedge clk)`
- Integer ranges → Use appropriate bit widths
- Division/modulo in indexing → Keep as-is (synthesis tool will optimize)

#### 2.4 Convert `xoodoo_n_rounds.vhd` → `xoodoo_n_rounds.sv`
**VHDL Features to Convert:**
- **Generic parameter**: `roundPerCycle : integer := roundsPerCycle`
- **Generate statement** with conditional: `if I > 0 generate`
- **Array of components**: Multiple instances in loop
- **Array type declarations**: `state_rounds`, `state_rc_rounds`, `rc_rounds`

**Complexity:** ⭐⭐⭐ High - Parameterized generate with component instantiation

**Verilog Approach:**
```systemverilog
module xoodoo_n_rounds #(
  parameter int ROUND_PER_CYCLE = 3
) (
  input x_state_t state_in,
  output x_state_t state_out,
  input logic [5:0] rc_state_in,
  output logic [5:0] rc_state_out
);
  
  x_state_t [ROUND_PER_CYCLE-1:0] intermediate_states;
  logic [5:0] [ROUND_PER_CYCLE-1:0] rc_states;
  logic [31:0] [ROUND_PER_CYCLE-1:0] rc_values;
  
  // Instantiate first round
  xoodoo_round round_0 (
    .state_in(state_in),
    .rc(rc_values[0]),
    .state_out(intermediate_states[0])
  );
  
  xoodoo_rc rc_0 (
    .state_in(rc_state_in),
    .rc(rc_values[0]),
    .state_out(rc_states[0])
  );
  
  // Generate remaining rounds
  generate
    for (genvar i = 1; i < ROUND_PER_CYCLE; i++) begin : gen_rounds
      xoodoo_round round_i (
        .state_in(intermediate_states[i-1]),
        .rc(rc_values[i]),
        .state_out(intermediate_states[i])
      );
      
      xoodoo_rc rc_i (
        .state_in(rc_states[i-1]),
        .rc(rc_values[i]),
        .state_out(rc_states[i])
      );
    end
  endgenerate
  
  assign state_out = intermediate_states[ROUND_PER_CYCLE-1];
  assign rc_state_out = rc_states[ROUND_PER_CYCLE-1];
endmodule
```

#### 2.5 Convert `xoodoo.vhd` → `xoodoo.sv`
**VHDL Features to Convert:**
- **Generic parameter** with default
- **Component instantiation**
- **Clock process** for state machine (done/running)
- **Signal assignments**

**Complexity:** ⭐⭐ Medium - State machine and component integration

**Key Conversions:**
- VHDL generic → Verilog parameter
- Component → Module instantiation
- Process → `always_ff` block

---

### Phase 3: LWC Interface Components
**SKIPPED - Not converting LWC components per requirements**

**Note:** LWC components (PreProcessor, PostProcessor, LWC wrapper, etc.) are NIST API compliance modules and are excluded from this conversion. The core Xoodyak functionality in `CryptoCore` is standalone and only requires header type constants from NIST_LWAPI_pkg, which will be included in `design_pkg.sv`.

---

### Phase 4: Top-Level Module

#### 4.1 Convert `CryptoCore.vhd` → `CryptoCore.sv`
**VHDL Features to Convert:**
- **Large state machine**: IDLE, STORE_KEY, ABSORB_NONCE, ABSORB_AD, etc.
- **Multiple process blocks**: Combinational and sequential
- **Complex control logic**: Handshaking, counters, multiplexers
- **Type conversions**: Between std_logic_vector and x_state_type
- **Function calls**: From design_pkg

**Complexity:** ⭐⭐⭐⭐ Very High - Large FSM with complex control logic

**Key Conversions:**
- Enum types → `typedef enum` or `localparam` states
- Multiple processes → `always_comb` and `always_ff` blocks
- Function calls → SystemVerilog function calls (from package)
- Type conversions → Use functions from xoodoo_globals

---

## Conversion Order (Recommended)

### **Step 1: Foundation (Packages)**
1. ✅ `xoodoo_globals.vhd` → `xoodoo_globals.sv`
2. ✅ `design_pkg.vhd` → `design_pkg.sv` (include NIST header constants directly, no separate NIST_LWAPI_pkg needed)

### **Step 2: Xoodoo Core (Bottom-Up)**
4. ✅ `xoodoo_rc.vhd` → `xoodoo_rc.sv` (no dependencies)
5. ✅ `xoodoo_round.vhd` → `xoodoo_round.sv` (depends on xoodoo_globals)
6. ✅ `xoodoo_register.vhd` → `xoodoo_register.sv` (depends on xoodoo_globals)
7. ✅ `xoodoo_n_rounds.vhd` → `xoodoo_n_rounds.sv` (depends on xoodoo_round, xoodoo_rc)
8. ✅ `xoodoo.vhd` → `xoodoo.sv` (depends on xoodoo_n_rounds, xoodoo_register)

### **Step 3: Top-Level**
9. ✅ `CryptoCore.vhd` → `CryptoCore.sv` (depends on Xoodoo core modules and packages)

---

## Key VHDL-to-Verilog Conversion Patterns

### 1. **Type Definitions**
```vhdl
-- VHDL
type x_plane_type is array (0 to 3) of std_logic_vector(31 downto 0);
type x_state_type is array (0 to 2) of x_plane_type;
```
```systemverilog
// SystemVerilog
typedef logic [31:0] x_word_t;
typedef x_word_t [0:3] x_plane_t;
typedef x_plane_t [0:2] x_state_t;
```

### 2. **Generics/Parameters**
```vhdl
-- VHDL
generic( roundPerCycle : integer := 1);
```
```systemverilog
// SystemVerilog
parameter int ROUND_PER_CYCLE = 1;
```

### 3. **Processes**
```vhdl
-- VHDL
process(clk)
begin
  if rising_edge(clk) then
    if rst = '1' then
      reg <= '0';
    else
      reg <= next_reg;
    end if;
  end if;
end process;
```
```systemverilog
// SystemVerilog
always_ff @(posedge clk) begin
  if (rst) begin
    reg <= '0;
  end else begin
    reg <= next_reg;
  end
end
```

### 4. **Generate Loops**
```vhdl
-- VHDL
i0101: for x in 0 to 3 generate
  signal_array(x) <= input(x);
end generate;
```
```systemverilog
// SystemVerilog
generate
  for (genvar x = 0; x < 4; x++) begin : gen_label
    assign signal_array[x] = input[x];
  end
endgenerate
```

### 5. **Functions**
```vhdl
-- VHDL
function get_words(size: integer; iowidth:integer) return integer is
begin
  if (size mod iowidth) > 0 then
    return size/iowidth + 1;
  else
    return size/iowidth;
  end if;
end function;
```
```systemverilog
// SystemVerilog
function automatic int get_words(int size, int iowidth);
  if ((size % iowidth) > 0)
    return size/iowidth + 1;
  else
    return size/iowidth;
endfunction
```

### 6. **Modulo Operations**
```vhdl
-- VHDL
signal_out <= signal_in((x-1) mod 4);
```
```systemverilog
// SystemVerilog
// For mod 4 (2 bits), use:
assign signal_out = signal_in[(x-1+4) & 3];
// Or more general:
assign signal_out = signal_in[((x-1) % 4)];
// Note: Synthesis tools handle % operator for power-of-2 moduli
```

### 7. **Integer Ranges**
```vhdl
-- VHDL
word_index_in : in integer range 0 to 11;
```
```systemverilog
// SystemVerilog
input logic [3:0] word_index_in;  // 4 bits covers 0-15
// Or use parameterized type:
input logic [$clog2(12)-1:0] word_index_in;
```

---

## Testing Strategy

### Unit Testing
- Test each converted module in isolation
- Compare simulation outputs with VHDL version
- Use testbenches for each component

### Integration Testing
- Test Xoodoo permutation end-to-end
- Test CryptoCore with known test vectors
- Verify against NIST test vectors

### Verification Checklist
- [ ] All packages compile without errors
- [ ] Xoodoo core components simulate correctly
- [ ] Round constants match VHDL version
- [ ] State conversions (to/from std_logic_vector) work correctly
- [ ] CryptoCore state machine behaves identically
- [ ] All generic/parameter instantiations work
- [ ] Synthesis produces equivalent hardware

---

## File Naming Convention

### Verilog/SystemVerilog Files:
- Packages: `*.sv` (SystemVerilog for package support)
- Modules: `*.sv` or `*.v` (prefer `.sv` for SystemVerilog features)
- Lowercase filenames: `xoodoo_round.sv` (match VHDL style or use snake_case)

### Recommended Structure:
```
src_rtl/
├── xoodoo_globals.sv          (from xoodoo_globals.vhd)
├── design_pkg.sv              (from design_pkg.vhd, includes NIST header constants)
├── xoodoo_rc.sv               (from xoodoo_rc.vhd)
├── xoodoo_round.sv            (from xoodoo_round.vhd)
├── xoodoo_register.sv         (from xoodoo_register.vhd)
├── xoodoo_n_rounds.sv         (from xoodoo_n_rounds.vhd)
├── xoodoo.sv                  (from xoodoo.vhd)
├── CryptoCore.sv              (from CryptoCore.vhd)
└── LWC/
    ├── nist_lwapi_pkg.sv      (from NIST_LWAPI_pkg.vhd)
    ├── step_down_count_ld.sv  (from StepDownCountLd.vhd)
    ├── key_piso.sv            (from key_piso.vhd)
    ├── data_piso.sv           (from data_piso.vhd)
    ├── data_sipo.sv           (from data_sipo.sv)
    ├── fwft_fifo.sv           (from fwft_fifo.vhd)
    ├── pre_processor.sv       (from PreProcessor.vhd)
    ├── post_processor.sv      (from PostProcessor.vhd)
    └── lwc.sv                 (from LWC.vhd)
```

---

## Challenges and Considerations

### 1. **Array Indexing**
- VHDL uses `(0 to N-1)` vs Verilog `[0:N-1]` or `[N-1:0]`
- Pay attention to bit ordering consistency

### 2. **Modulo Operations in Synthesis**
- Verilog `%` operator synthesis depends on tool
- For power-of-2 moduli, prefer bit masking: `& (N-1)`
- Document assumptions about modulo operations

### 3. **3D Arrays**
- SystemVerilog typedefs help but syntax differs
- Ensure bit ordering matches VHDL implementation

### 4. **Generate Blocks**
- Verilog generate syntax is similar but has differences
- Conditional generates need careful translation

### 5. **Integer Types**
- VHDL integer ranges vs Verilog bit-width requirements
- Use appropriate bit widths to avoid synthesis issues

### 6. **Package Usage**
- SystemVerilog packages vs VHDL packages
- Import statements differ: `import design_pkg::*;`

### 7. **Function Calls**
- VHDL functions can be in packages
- SystemVerilog functions in packages need proper import

---

## Tools and Resources

### Recommended Tools:
- **Simulation**: ModelSim/QuestaSim, VCS, Xcelium
- **Synthesis**: Synplify, Design Compiler, Vivado
- **Linting**: Verilator, Spyglass

### Reference Materials:
- SystemVerilog LRM (IEEE 1800)
- Verilog-2005/SystemVerilog conversion guides
- Xoodyak specification document

---

## Timeline Estimate

### Phase 1 (Packages): 1.5-2 days
- xoodoo_globals: 0.5 days
- design_pkg (including NIST header constants): 0.5-1 day
- Testing: 0.5 day

### Phase 2 (Xoodoo Core): 5-7 days
- xoodoo_rc: 0.5 days
- xoodoo_round: 1.5 days
- xoodoo_register: 1 day
- xoodoo_n_rounds: 1.5 days
- xoodoo: 1 day
- Testing: 1-2 days

### Phase 3 (CryptoCore): 7-10 days
- Conversion: 5-7 days
- Testing & debugging: 2-3 days

### **Total Estimate: 13.5-19 days** (approximately 3-4 weeks)

---

## Success Criteria

✅ All Verilog files compile without errors  
✅ All modules simulate correctly  
✅ Functional equivalence with VHDL version verified  
✅ Synthesis produces equivalent or better results  
✅ Test vectors pass for all modes (AEAD and hashing)  
✅ Documentation updated  
✅ Code follows Verilog/SystemVerilog best practices

---

## Notes

- Consider keeping VHDL and Verilog versions in sync during development
- Use version control to track changes
- Document any design decisions or workarounds
- Consider creating a comparison testbench to verify equivalence
- May want to create a script to automate some repetitive conversions

---

**Document Version:** 1.0  
**Date:** 2024  
**Author:** Conversion Plan

