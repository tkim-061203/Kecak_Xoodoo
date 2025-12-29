# Verilog (.v) vs SystemVerilog (.sv) Conversion Differences

## Current Plan Assumes SystemVerilog (.sv)

The current conversion plan uses **SystemVerilog (.sv)** features:
- **Packages** (`package`/`endpackage`)
- **Typedefs** for complex types
- **Functions in packages**
- Better type system

## If You Need Pure Verilog (.v) Files

If you need **Verilog-2001/2005 (.v)** files instead, here are the key differences:

### 1. **Packages → Include Files or Module Parameters**

**SystemVerilog (.sv) approach:**
```systemverilog
package xoodoo_globals;
  typedef logic [31:0] x_word_t;
  typedef x_word_t [0:3] x_plane_t;
  typedef x_plane_t [0:2] x_state_t;
  function logic [383:0] xstate_to_stdlogicvector(x_state_t state);
    // ...
  endfunction
endpackage

module xoodoo_round (...);
  import xoodoo_globals::*;
  input x_state_t state_in;
  // ...
endmodule
```

**Verilog (.v) approach:**
```verilog
// xoodoo_globals.vh (include file)
`define X_STATE_WIDTH 384
`define X_PLANE_WIDTH 128
`define X_WORD_WIDTH 32

// Use regular arrays: logic [X_STATE_WIDTH-1:0]
// Functions must be in modules or separate files
// OR define types as parameters in modules
```

**OR use module-level parameters:**
```verilog
module xoodoo_globals_func;
  function [383:0] xstate_to_stdlogicvector;
    input [383:0] state;
    // ...
  endfunction
endmodule
```

### 2. **Typedefs → Manual Type Definitions**

**SystemVerilog:**
```systemverilog
typedef logic [31:0] x_word_t;
typedef x_word_t [0:3] x_plane_t;
typedef x_plane_t [0:2] x_state_t;
```

**Verilog (.v):**
```verilog
// No typedefs - use arrays directly
// State: [383:0] or [0:383] (384 bits total)
// Access pattern: state[128*y + 32*x + i] for bit access
// OR use multi-dimensional arrays if supported (tool dependent)

// Manual indexing:
// state[y][x][i] → state[128*y + 32*x + i]
```

### 3. **Package Functions → Module Functions or Tasks**

**SystemVerilog:**
```systemverilog
package design_pkg;
  function automatic int get_words(int size, int iowidth);
    return (size % iowidth > 0) ? (size/iowidth + 1) : (size/iowidth);
  endfunction
endpackage
```

**Verilog (.v):**
```verilog
// Option 1: Functions in modules
module design_funcs;
  function integer get_words;
    input integer size, iowidth;
    begin
      if ((size % iowidth) > 0)
        get_words = size/iowidth + 1;
      else
        get_words = size/iowidth;
    end
  endfunction
endmodule

// Option 2: Use `define macros
`define get_words(size, iowidth) \
  ((size % iowidth > 0) ? (size/iowidth + 1) : (size/iowidth))

// Option 3: Inline the logic (no function)
```

### 4. **Constants → Parameters or `define**

**SystemVerilog:**
```systemverilog
package design_pkg;
  parameter int TAG_SIZE = 128;
  parameter logic [3:0] HDR_AD = 4'b0001;
endpackage
```

**Verilog (.v):**
```verilog
// Option 1: Parameters in modules
module design_params #(
  parameter TAG_SIZE = 128,
  parameter [3:0] HDR_AD = 4'b0001
) (...);

// Option 2: `define in include file
`define TAG_SIZE 128
`define HDR_AD 4'b0001

// Option 3: Localparam in modules
localparam TAG_SIZE = 128;
localparam [3:0] HDR_AD = 4'b0001;
```

### 5. **Complex Type Conversions**

**SystemVerilog:**
```systemverilog
input x_state_t state_in;  // Clean type
output logic [383:0] state_out;
assign state_out = xstate_to_stdlogicvector(state_in);
```

**Verilog (.v):**
```verilog
input [383:0] state_in;  // Raw bit vector
output [383:0] state_out;
// Manual bit assignment or use function from separate module
// OR use generate loops to assign bits
```

## Recommended Approach for Pure Verilog (.v)

### Option A: Include Files with Macros and Functions
1. Create `.vh` (Verilog header) files:
   - `xoodoo_globals.vh` - Type definitions as `define, function definitions
   - `design_pkg.vh` - Constants, macros, functions

2. Include in modules:
   ```verilog
   `include "xoodoo_globals.vh"
   `include "design_pkg.vh"
   ```

### Option B: Separate Function Modules
1. Create utility modules with functions
2. Instantiate or call functions from modules
3. Use parameters for constants

### Option C: Inline Everything
1. No separate packages/files
2. Define constants as parameters in each module
3. Inline function logic where needed
4. Use raw bit vectors instead of typedefs

## File Extensions

- **SystemVerilog**: `.sv` files (current plan)
- **Pure Verilog**: `.v` files + `.vh` include files (if needed)

## Recommendation

**If you need `.v` files:**
1. Use **Option A** (include files) for cleaner organization
2. Keep functions in separate modules that can be instantiated
3. Use `define for types and constants
4. Use parameters for module-specific constants

**Trade-offs:**
- `.sv`: Cleaner, more modern, better type safety, but requires SystemVerilog support
- `.v`: More portable, works with older tools, but requires more manual type management

## Updated File List for Verilog (.v)

If converting to pure Verilog:

```
src_rtl/
├── xoodoo_globals.vh          (include file with type definitions, functions)
├── design_pkg.vh              (include file with constants, macros, functions)
├── xoodoo_rc.v                (module)
├── xoodoo_round.v             (module, includes xoodoo_globals.vh)
├── xoodoo_register.v          (module, includes xoodoo_globals.vh)
├── xoodoo_n_rounds.v          (module, includes xoodoo_globals.vh, design_pkg.vh)
├── xoodoo.v                   (module, includes xoodoo_globals.vh)
└── CryptoCore.v               (module, includes xoodoo_globals.vh, design_pkg.vh)
```

**Note:** Conversion complexity increases significantly for pure Verilog due to:
- Manual bit indexing for 3D arrays
- No package system (need includes/functions in modules)
- Limited type system (no typedefs)
- More verbose code

## Which Do You Need?

Please specify:
- **`.sv`** files (SystemVerilog) - Current plan is optimized for this
- **`.v`** files (Pure Verilog) - Plan needs significant adjustments

The conversion strategy will differ based on your choice!

