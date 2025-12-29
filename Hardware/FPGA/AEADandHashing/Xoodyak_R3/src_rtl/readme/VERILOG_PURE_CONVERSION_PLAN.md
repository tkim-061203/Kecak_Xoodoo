# Pure Verilog (.v) Conversion Plan for Xoodyak_R3
## Using Separate Function Modules (Option B)

## Overview
This document outlines the plan to convert the VHDL implementation of Xoodyak_R3 to **Pure Verilog (.v)** files using **separate function modules**. This approach uses utility modules for shared functions rather than packages or include files.

**Scope:** Only core Xoodyak/Xoodoo components are converted. LWC directory components are excluded. NIST header constants will be defined as parameters or localparams in modules.

---

## Conversion Strategy: Pure Verilog with Function Modules

### Key Approach:
- **Packages → Utility Modules**: Functions will be in separate utility modules
- **Typedefs → Raw Bit Vectors**: Use `[383:0]` for state, manual indexing
- **Constants → Parameters/Localparams**: Module parameters or `define
- **Functions → Module Functions**: Separate modules with functions that can be instantiated or called

---

## File Structure

```
src_rtl/
├── xoodoo_types.vh            (optional: `define macros for widths, if needed)
├── xoodoo_globals_func.v      (utility module with state conversion functions)
├── design_funcs.v             (utility module with design_pkg functions)
├── xoodoo_rc.v                (round constant generator)
├── xoodoo_round.v             (single Xoodoo round)
├── xoodoo_register.v          (state register)
├── xoodoo_n_rounds.v          (multiple rounds per cycle)
├── xoodoo.v                   (top-level Xoodoo permutation)
└── CryptoCore.v               (main Xoodyak crypto core)
```

**Total: 9 files** (8 modules + 1 optional header)

---

## Phase 1: Foundation (Types, Constants, Functions)

### 1.1 Create `xoodoo_types.vh` (Optional Header File)
**Purpose:** Define bit widths and constants as `define macros (optional, can inline in modules)

**Content:**
```verilog
// Xoodoo state dimensions
`define X_STATE_WIDTH 384
`define X_PLANE_WIDTH 128
`define X_WORD_WIDTH 32
`define X_PLANE_WORDS 4
`define X_STATE_PLANES 3

// State indexing macros (helper macros)
// For state[y][x][i] → state[128*y + 32*x + i]
// Note: Verilog uses [383:0] for full state
```

**Note:** This is optional. Can also use parameters in each module or inline constants.

---

### 1.2 Convert `xoodoo_globals.vhd` → `xoodoo_globals_func.v`
**VHDL Features to Convert:**
- **Functions**: `xstate_to_stdlogicvector()`, `stdlogicvector_to_xstate()`
- **Constants**: `active_rst`, `ZERO_STATE`

**Verilog Approach - Separate Function Module:**
```verilog
module xoodoo_globals_func;
    // State conversion functions
    
    // Convert x_state_type (3D array) to std_logic_vector(383:0)
    function [383:0] xstate_to_stdlogicvector;
        input [383:0] state_in;  // Input as flat 384-bit vector
        integer y, x, i;
        begin
            xstate_to_stdlogicvector = 384'b0;
            // Manual bit assignment based on VHDL pattern:
            // retval(128*y+32*x+i) := state_type_i(y)(x)(i)
            for (y = 0; y < 3; y = y + 1) begin
                for (x = 0; x < 4; x = x + 1) begin
                    for (i = 0; i < 32; i = i + 1) begin
                        xstate_to_stdlogicvector[128*y + 32*x + i] = 
                            state_in[128*y + 32*x + i];
                    end
                end
            end
        end
    endfunction
    
    // Convert std_logic_vector(383:0) to x_state_type
    // This is essentially a pass-through in Verilog (same representation)
    function [383:0] stdlogicvector_to_xstate;
        input [383:0] slv_in;
        begin
            stdlogicvector_to_xstate = slv_in;
        end
    endfunction
    
endmodule
```

**Usage Pattern:**
```verilog
module some_module (...);
    // Instantiate or use functions via module instantiation
    // OR: Functions can be in a separate file and included conceptually
    // In practice: May need to inline functions or use parameterized modules
endmodule
```

**Alternative Approach (More Practical):**
Since Verilog functions can't be easily shared across modules, we can:
1. **Option 1:** Inline the conversion logic where needed (for state conversions, they're mostly pass-through)
2. **Option 2:** Create parameterized helper modules
3. **Option 3:** Use task-based modules for complex operations

**For this conversion, we'll use a hybrid:**
- Simple conversions: Inline (they're mostly pass-through in Verilog)
- Complex functions: Separate utility modules with tasks/functions

---

### 1.3 Convert `design_pkg.vhd` → `design_funcs.v` + Module Parameters
**VHDL Features to Convert:**
- **Constants**: `roundsPerCycle`, `TAG_SIZE`, `KEY_SIZE`, `NPUB_SIZE`, etc.
- **Functions**: `get_words()`, `log2_ceil()`, `reverse_byte()`, `reverse_bit()`, `padd()`, `max()`, `domain_word()`, `select_bytes()`
- **NIST Header Constants**: `HDR_AD`, `HDR_NPUB`, `HDR_PT`, `HDR_CT`, `HDR_TAG`, `HDR_HASH_VALUE`, `HDR_HASH_MSG`

**Verilog Approach:**

**For Constants:** Use `define in a header or parameters in modules
```verilog
// design_params.vh (optional, or use parameters in modules)
`define ROUNDS_PER_CYCLE 3
`define TAG_SIZE 128
`define KEY_SIZE 128
`define NPUB_SIZE 128
`define STATE_SIZE 384
`define DBLK_SIZE 352
`define RKIN 352
`define RKOUT 192
`define RHASH 128
`define CCW 32
`define CCSW 32
`define CCWdiv8 4

// NIST Header Type Constants
`define HDR_AD         4'b0001
`define HDR_NPUB       4'b1101
`define HDR_PT         4'b0100
`define HDR_CT         4'b0101
`define HDR_TAG        4'b1000
`define HDR_HASH_VALUE 4'b1001
`define HDR_HASH_MSG   4'b0111
```

**For Functions:** Separate utility module
```verilog
module design_funcs;
    // Calculate number of words
    function integer get_words;
        input integer size;
        input integer iowidth;
        begin
            if ((size % iowidth) > 0)
                get_words = size / iowidth + 1;
            else
                get_words = size / iowidth;
        end
    endfunction
    
    // Log base 2, rounded up
    function integer log2_ceil;
        input integer N;
        integer temp;
        begin
            if (N == 0)
                log2_ceil = 0;
            else if (N <= 2)
                log2_ceil = 1;
            else begin
                temp = N;
                log2_ceil = 0;
                while (temp > 1) begin
                    log2_ceil = log2_ceil + 1;
                    temp = temp >> 1;
                end
                if ((N & (N - 1)) != 0)  // Not power of 2
                    log2_ceil = log2_ceil + 1;
            end
        end
    endfunction
    
    // Reverse byte order
    function [31:0] reverse_byte;
        input [31:0] vec;
        integer i;
        begin
            for (i = 0; i < 4; i = i + 1) begin
                reverse_byte[8*(i+1)-1:8*i] = vec[8*(4-i)-1:8*(3-i)];
            end
        end
    endfunction
    
    // Reverse bit order
    function [31:0] reverse_bit;
        input [31:0] vec;
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1) begin
                reverse_bit[i] = vec[31-i];
            end
        end
    endfunction
    
    // Padding function
    function [31:0] padd;
        input [31:0] bdi;
        input [3:0] bdi_valid_bytes;
        input [3:0] bdi_pad_loc;
        integer i;
        begin
            padd = 32'b0;
            for (i = 0; i < 4; i = i + 1) begin
                if (bdi_valid_bytes[i])
                    padd[8*(i+1)-1:8*i] = bdi[8*(i+1)-1:8*i];
                else if (bdi_pad_loc[i])
                    padd[8*(i+1)-1:8*i] = 8'h01;
            end
        end
    endfunction
    
    // Max function
    function integer max;
        input integer a;
        input integer b;
        begin
            if (a >= b)
                max = a;
            else
                max = b;
        end
    endfunction
    
    // Domain word from command
    function [31:0] domain_word;
        input [7:0] CMD;
        begin
            domain_word = {CMD, 24'b0};
        end
    endfunction
    
    // Select bytes function
    function [31:0] select_bytes;
        input [31:0] bdi;
        input [3:0] bdi_valid_bytes;
        integer i;
        begin
            select_bytes = 32'b0;
            for (i = 0; i < 4; i = i + 1) begin
                if (bdi_valid_bytes[i])
                    select_bytes[8*(i+1)-1:8*i] = 8'b0;
                else
                    select_bytes[8*(i+1)-1:8*i] = 8'hFF;
            end
        end
    endfunction
    
endmodule
```

**Note:** Since functions in modules can't be easily shared, we have two practical options:

1. **Inline functions** where they're used (simpler for synthesis)
2. **Use tasks** in a separate module that gets instantiated (more complex)

**For this conversion, we'll:**
- Inline simple functions directly in modules (e.g., `max`, `domain_word`)
- Keep complex utility functions as separate modules that can be referenced
- Use `define for constants or parameters in each module

---

## Phase 2: Xoodoo Core Components

### 2.1 Convert `xoodoo_rc.vhd` → `xoodoo_rc.v`

**Key Conversions:**
- VHDL `std_logic_vector` → Verilog `wire`/`reg` or `logic` (use `reg` in Verilog-2001)
- VHDL `unsigned` → Verilog arithmetic operations
- VHDL `case` → Verilog `case`
- Combinational logic → `always @(*)` or `assign`

**Structure:**
```verilog
module xoodoo_rc (
    input [5:0] state_in,
    output reg [5:0] state_out,
    output reg [31:0] rc
);

    reg [2:0] si;
    reg [3:0] temp_new_si;
    reg [2:0] new_si;
    reg [2:0] qi;
    reg [2:0] new_qi;
    reg [3:0] qi_plus_t3;

    always @(*) begin
        si = state_in[2:0];
        temp_new_si = si + {si[1:0], si[2]};
        new_si = temp_new_si[2:0] + temp_new_si[3];
        
        qi = state_in[5:3];
        new_qi[0] = qi[2];
        new_qi[1] = qi[0] ^ qi[2];
        new_qi[2] = qi[1];
        
        qi_plus_t3 = {qi, 1'b1};
        
        // Round constant generation
        rc[31:10] = 22'b0;
        case (si)
            3'b001: rc[9:0] = {5'b0, qi_plus_t3};
            3'b010: rc[9:0] = {4'b0, qi_plus_t3, 1'b0};
            3'b011: rc[9:0] = {3'b0, qi_plus_t3, 2'b0};
            3'b100: rc[9:0] = {2'b0, qi_plus_t3, 3'b0};
            3'b101: rc[9:0] = {1'b0, qi_plus_t3, 4'b0};
            3'b110: rc[9:0] = {qi_plus_t3, 5'b0};
            default: rc[9:0] = 10'b0;
        endcase
        
        state_out = {new_qi, new_si};
    end

endmodule
```

---

### 2.2 Convert `xoodoo_round.vhd` → `xoodoo_round.v`

**Key Conversions:**
- **3D Array Access**: VHDL `state(y)(x)(i)` → Verilog `state[128*y + 32*x + i]`
- **Modulo Operations**: `(x-1) mod 4` → `((x-1+4) & 3)` or `((x-1) % 4)`
- **Generate Loops**: VHDL `for x in 0 to 3 generate` → Verilog `generate for`

**Structure:**
```verilog
module xoodoo_round (
    input [383:0] state_in,  // 384-bit flat state
    input [31:0] rc,
    output reg [383:0] state_out
);

    // Intermediate states (all as 384-bit vectors)
    reg [383:0] theta_in, theta_out;
    reg [383:0] rho_w_in, rho_w_out;
    reg [383:0] iota_in, iota_out;
    reg [383:0] chi_in, chi_out;
    
    // Parity planes (4 planes × 32 bits = 128 bits)
    reg [127:0] p, e;
    
    integer x, i, y;
    integer idx_p, idx_e, idx_state;
    
    always @(*) begin
        theta_in = state_in;
        
        // Theta: Compute parity planes
        for (x = 0; x < 4; x = x + 1) begin
            for (i = 0; i < 32; i = i + 1) begin
                idx_p = 32*x + i;
                p[idx_p] = theta_in[0*128 + idx_p] ^ 
                          theta_in[1*128 + idx_p] ^ 
                          theta_in[2*128 + idx_p];
            end
        end
        
        // Theta: Compute e planes
        for (x = 0; x < 4; x = x + 1) begin
            for (i = 0; i < 32; i = i + 1) begin
                idx_e = 32*x + i;
                idx_p = 32*((x+3) % 4) + ((i+27) % 32);  // (x-1) mod 4, (i-5) mod 32
                p[idx_p] = theta_in[0*128 + idx_p] ^ 
                          theta_in[1*128 + idx_p] ^ 
                          theta_in[2*128 + idx_p];
                idx_p = 32*((x+3) % 4) + ((i+18) % 32);  // (x-1) mod 4, (i-14) mod 32
                e[idx_e] = p[idx_p] ^ p[32*((x+3) % 4) + ((i+18) % 32)];
            end
        end
        
        // Theta: Add e to state
        for (y = 0; y < 3; y = y + 1) begin
            for (x = 0; x < 4; x = x + 1) begin
                for (i = 0; i < 32; i = i + 1) begin
                    idx_state = 128*y + 32*x + i;
                    theta_out[idx_state] = theta_in[idx_state] ^ e[32*x + i];
                end
            end
        end
        
        // Rho West
        rho_w_in = theta_out;
        for (y = 0; y < 3; y = y + 1) begin
            for (x = 0; x < 4; x = x + 1) begin
                for (i = 0; i < 32; i = i + 1) begin
                    idx_state = 128*y + 32*x + i;
                    if (y == 0)
                        rho_w_out[idx_state] = rho_w_in[idx_state];
                    else if (y == 1)
                        rho_w_out[idx_state] = rho_w_in[128*1 + 32*((x+3) % 4) + i];
                    else // y == 2
                        rho_w_out[idx_state] = rho_w_in[128*2 + 32*x + ((i+21) % 32)];
                end
            end
        end
        
        // Iota
        iota_in = rho_w_out;
        iota_out = iota_in;
        for (i = 0; i < 32; i = i + 1) begin
            iota_out[0*128 + 0*32 + i] = iota_in[0*128 + 0*32 + i] ^ rc[i];
        end
        
        // Chi
        chi_in = iota_out;
        for (x = 0; x < 4; x = x + 1) begin
            for (i = 0; i < 32; i = i + 1) begin
                chi_out[0*128 + 32*x + i] = chi_in[0*128 + 32*x + i] ^ 
                                           (~chi_in[1*128 + 32*x + i] & chi_in[2*128 + 32*x + i]);
                chi_out[1*128 + 32*x + i] = chi_in[1*128 + 32*x + i] ^ 
                                           (~chi_in[2*128 + 32*x + i] & chi_in[0*128 + 32*x + i]);
                chi_out[2*128 + 32*x + i] = chi_in[2*128 + 32*x + i] ^ 
                                           (~chi_in[0*128 + 32*x + i] & chi_in[1*128 + 32*x + i]);
            end
        end
        
        // Rho East
        rho_e_in = chi_out;
        for (y = 0; y < 3; y = y + 1) begin
            for (x = 0; x < 4; x = x + 1) begin
                for (i = 0; i < 32; i = i + 1) begin
                    idx_state = 128*y + 32*x + i;
                    if (y == 0)
                        rho_e_out[idx_state] = rho_e_in[idx_state];
                    else if (y == 1)
                        rho_e_out[idx_state] = rho_e_in[128*1 + 32*x + ((i+31) % 32)];
                    else // y == 2
                        rho_e_out[idx_state] = rho_e_in[128*2 + 32*((x+2) % 4) + ((i+24) % 32)];
                end
            end
        end
        
        state_out = rho_e_out;
    end

endmodule
```

**Note:** This is complex due to 3D array flattening. May need careful testing to ensure bit ordering matches VHDL.

---

### 2.3 Convert `xoodoo_register.vhd` → `xoodoo_register.v`

**Key Conversions:**
- VHDL process → `always @(posedge clk)`
- Integer range → appropriate bit width
- Division/modulo in indexing → Keep as-is (synthesis will optimize)

**Structure:**
```verilog
module xoodoo_register (
    input clk,
    input rst,
    input init,
    input [383:0] state_in,
    output reg [383:0] state_out,
    input [31:0] word_in,
    input [3:0] word_index_in,  // 4 bits for 0-11
    input word_enable_in,
    input start_in,
    input running_in,
    input [31:0] domain_i,
    input domain_enable_i,
    output [31:0] word_out
);

    reg [383:0] reg_value;
    integer word_y, word_x;
    
    always @(posedge clk) begin
        if (rst) begin
            reg_value <= 384'b0;
        end else begin
            if (init) begin
                reg_value <= 384'b0;
            end else if (running_in || start_in) begin
                reg_value <= state_in;
            end else begin
                if (domain_enable_i) begin
                    reg_value[128*2 + 32*3 +: 32] <= reg_value[128*2 + 32*3 +: 32] ^ domain_i;
                end
                if (word_enable_in) begin
                    word_y = word_index_in / 4;
                    word_x = word_index_in % 4;
                    reg_value[128*word_y + 32*word_x +: 32] <= 
                        reg_value[128*word_y + 32*word_x +: 32] ^ word_in;
                end
            end
        end
    end
    
    assign state_out = reg_value;
    
    // Output word (combinational)
    always @(*) begin
        word_y = word_index_in / 4;
        word_x = word_index_in % 4;
        word_out = reg_value[128*word_y + 32*word_x +: 32];
    end

endmodule
```

---

### 2.4 Convert `xoodoo_n_rounds.vhd` → `xoodoo_n_rounds.v`

**Key Conversions:**
- Generic parameter → `parameter`
- Generate with arrays → `generate` loop
- Component arrays → Array of instances

**Structure:**
```verilog
module xoodoo_n_rounds #(
    parameter ROUND_PER_CYCLE = 3
) (
    input [383:0] state_in,
    output [383:0] state_out,
    input [5:0] rc_state_in,
    output [5:0] rc_state_out
);

    // Array of intermediate states
    wire [383:0] intermediate_states [0:ROUND_PER_CYCLE-1];
    wire [5:0] rc_states [0:ROUND_PER_CYCLE-1];
    wire [31:0] rc_values [0:ROUND_PER_CYCLE-1];
    
    // First round
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
        genvar i;
        for (i = 1; i < ROUND_PER_CYCLE; i = i + 1) begin : gen_rounds
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

---

### 2.5 Convert `xoodoo.vhd` → `xoodoo.v`

**Key Conversions:**
- Generic → `parameter`
- Component → Module instantiation
- Process → `always @(posedge clk)`

**Structure:**
```verilog
module xoodoo #(
    parameter ROUND_PER_CYCLE = 3
) (
    input clk_i,
    input rst_i,
    input start_i,
    output state_valid_o,
    input init_reg,
    input [31:0] word_in,
    input [3:0] word_index_in,
    input word_enable_in,
    input [31:0] domain_i,
    input domain_enable_i,
    output [31:0] word_out
);

    wire [383:0] round_in, round_out, reg_in, reg_out;
    wire [5:0] rc_state_in, rc_state_out;
    reg done, running;
    reg [5:0] rc_state_reg;
    
    xoodoo_register rg00_map (
        .clk(clk_i),
        .rst(rst_i),
        .init(init_reg),
        .state_in(reg_in),
        .state_out(reg_out),
        .word_in(word_in),
        .word_index_in(word_index_in),
        .word_enable_in(word_enable_in),
        .start_in(start_i),
        .running_in(running),
        .domain_i(domain_i),
        .domain_enable_i(domain_enable_i),
        .word_out(word_out)
    );
    
    xoodoo_n_rounds rd00_map #(
        .ROUND_PER_CYCLE(ROUND_PER_CYCLE)
    ) (
        .state_in(round_in),
        .state_out(round_out),
        .rc_state_in(rc_state_in),
        .rc_state_out(rc_state_out)
    );
    
    always @(posedge clk_i) begin
        if (rst_i) begin
            done <= 1'b0;
            running <= 1'b0;
            rc_state_reg <= 6'b011011;
        end else begin
            if (start_i) begin
                done <= 1'b0;
                running <= 1'b1;
                rc_state_reg <= rc_state_out;
            end else if (running) begin
                done <= 1'b0;
                running <= 1'b1;
                rc_state_reg <= rc_state_out;
            end
            
            if (rc_state_out == 6'b010011) begin
                done <= 1'b1;
                running <= 1'b0;
                rc_state_reg <= 6'b011011;
            end
        end
    end
    
    assign round_in = reg_out;
    assign reg_in = round_out;
    assign state_valid_o = done;
    assign rc_state_in = (start_i || running) ? rc_state_reg : 6'b011011;

endmodule
```

---

## Phase 3: Top-Level Module

### 3.1 Convert `CryptoCore.vhd` → `CryptoCore.v`

**Key Conversions:**
- Enum type → `localparam` states
- Multiple processes → `always @(*)` and `always @(posedge clk)`
- Function calls → Inline functions or use from utility modules
- Type conversions → Manual bit manipulation

**Structure:** (Large module, similar patterns to above)
- State machine with `localparam` states
- Combinational logic in `always @(*)`
- Sequential logic in `always @(posedge clk)`
- Inline function logic where needed
- Use `define or parameters for constants

---

## Conversion Order (Updated for Pure Verilog)

### **Step 1: Foundation**
1. ✅ Create `xoodoo_types.vh` (optional, `define macros)
2. ✅ `xoodoo_globals.vhd` → `xoodoo_globals_func.v` (utility module, or inline)
3. ✅ Create `design_params.vh` (constants) or use parameters
4. ✅ `design_pkg.vhd` → `design_funcs.v` (utility module, or inline functions)

### **Step 2: Xoodoo Core (Bottom-Up)**
5. ✅ `xoodoo_rc.vhd` → `xoodoo_rc.v`
6. ✅ `xoodoo_round.vhd` → `xoodoo_round.v` (complex 3D array handling)
7. ✅ `xoodoo_register.vhd` → `xoodoo_register.v`
8. ✅ `xoodoo_n_rounds.vhd` → `xoodoo_n_rounds.v`
9. ✅ `xoodoo.vhd` → `xoodoo.v`

### **Step 3: Top-Level**
10. ✅ `CryptoCore.vhd` → `CryptoCore.v`

---

## Key Differences from SystemVerilog Plan

| Feature | SystemVerilog (.sv) | Pure Verilog (.v) - Option B |
|---------|---------------------|------------------------------|
| Packages | ✅ `package` | ❌ Separate function modules |
| Typedefs | ✅ `typedef` | ❌ Raw bit vectors `[383:0]` |
| Functions | ✅ In packages | ❌ In utility modules or inline |
| Constants | ✅ `parameter` in packages | ✅ `define or module parameters |
| Type Safety | ✅ Strong typing | ⚠️ Manual bit management |
| Code Size | ✅ Compact | ⚠️ More verbose |

---

## Challenges for Pure Verilog

1. **3D Array Flattening**: Must manually calculate indices `[128*y + 32*x + i]`
2. **Function Sharing**: Functions in modules aren't easily shareable → inline or use utility modules
3. **Type Conversions**: Manual bit manipulation instead of clean type conversions
4. **More Verbose**: More lines of code due to explicit indexing

---

## Timeline Estimate (Updated)

- **Phase 1 (Foundation):** 2-3 days (function modules + constants)
- **Phase 2 (Xoodoo Core):** 6-8 days (more complex due to array flattening)
- **Phase 3 (CryptoCore):** 8-11 days (large FSM + manual conversions)
- **Total:** 16-22 days (approximately 3-4 weeks)

---

**Document Version:** 1.0 (Pure Verilog Option B)  
**Date:** 2024

