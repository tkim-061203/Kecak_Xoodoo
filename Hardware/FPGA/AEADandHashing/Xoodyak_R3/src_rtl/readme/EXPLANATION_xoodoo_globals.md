# Explanation of xoodoo_globals.vhd

## Overview

This is a **VHDL package** file that defines the fundamental data types, constants, and utility functions for the Xoodoo permutation algorithm. It serves as a shared library that other Xoodoo modules can use.

---

## File Structure

The file has two parts:
1. **Package Declaration** (lines 22-38): Declares what's available
2. **Package Body** (lines 40-74): Implements the declared items

---

## Package Declaration (lines 22-38)

### 1. Constant Declaration
```vhdl
constant active_rst : std_logic;
```
- Declares a constant for active reset level (defined in package body as `'1'`)
- Used throughout Xoodoo modules for reset signal checking

### 2. Type Definitions

#### `x_plane_type` (line 27)
```vhdl
type x_plane_type is array (0 to 3) of std_logic_vector(31 downto 0);
```
- Defines a **plane** in the Xoodoo state
- Structure: **4 words × 32 bits = 128 bits**
- Represents one "layer" of the Xoodoo state

#### `x_state_type` (line 28)
```vhdl
type x_state_type is array (0 to 2) of x_plane_type;
```
- Defines the complete **Xoodoo state**
- Structure: **3 planes × 4 words × 32 bits = 384 bits total**
- This is a **3-dimensional array**:
  - `x_state_type(y)(x)(i)` where:
    - `y` = plane index (0 to 2)
    - `x` = word index within plane (0 to 3)
    - `i` = bit index within word (0 to 31)

**Visual Representation:**
```
Xoodoo State (384 bits total)

Plane y=2:  [word0] [word1] [word2] [word3]   (128 bits)
Plane y=1:  [word0] [word1] [word2] [word3]   (128 bits)
Plane y=0:  [word0] [word1] [word2] [word3]   (128 bits)
            (32b)   (32b)   (32b)   (32b)
```

### 3. Function Declarations

#### `xstate_to_stdlogicvector()` (line 30-31)
- Converts from `x_state_type` (3D array) to `std_logic_vector(383 downto 0)` (flat 384-bit vector)
- Used when you need to pass the state as a simple bit vector

#### `stdlogicvector_to_xstate()` (line 33-34)
- Converts from `std_logic_vector(383 downto 0)` (flat vector) to `x_state_type` (3D array)
- Inverse of the above function

### 4. Constant Declaration
```vhdl
constant ZERO_STATE : x_state_type;
```
- A constant representing the all-zero state (384 bits of zeros)
- Useful for initialization

---

## Package Body (Implementation)

### 1. Active Reset Constant (line 42)
```vhdl
constant active_rst : std_logic := '1';
```
- Defines active reset as HIGH (`'1'`)
- When `rst = '1'`, the circuit resets

### 2. `xstate_to_stdlogicvector()` Function (lines 44-56)

**Purpose:** Converts 3D array state to flat 384-bit vector

**Mapping Formula:**
```
bit_position = 128*y + 32*x + i
```

Where:
- `y` = plane index (0, 1, or 2)
- `x` = word index (0, 1, 2, or 3)
- `i` = bit index (0 to 31)

**Example:**
- `state(1)(2)(5)` (plane 1, word 2, bit 5) maps to:
  - `retval[128*1 + 32*2 + 5] = retval[197]`

**Why this formula?**
- Each plane is 128 bits (4 words × 32 bits)
- So plane `y` starts at bit `128*y`
- Within plane, word `x` starts at `32*x`
- Within word, bit `i` is at position `i`

### 3. `stdlogicvector_to_xstate()` Function (lines 58-70)

**Purpose:** Converts flat 384-bit vector to 3D array state

**Inverse Mapping:**
- Uses the same formula in reverse
- `retval(y)(x)(i) = slv_i(128*y + 32*x + i)`

### 4. ZERO_STATE Constant (line 72)

```vhdl
constant ZERO_STATE : x_state_type := stdlogicvector_to_xstate(x"00...00");
```

- Creates an all-zero state using the conversion function
- The hex value is 96 hex digits = 384 bits of zeros
- Useful for initialization: `state <= ZERO_STATE;`

---

## How Xoodoo State is Organized

### Physical Layout in Memory:
```
Bits [383:0] when flattened:
[383:256]  Plane 2 (y=2): words [3,2,1,0]
[255:128]  Plane 1 (y=1): words [3,2,1,0]
[127:0]    Plane 0 (y=0): words [3,2,1,0]
```

### Access Pattern:
- **VHDL (3D array):** `state(y)(x)(i)` - clean, readable
- **Verilog equivalent:** `state[128*y + 32*x + i]` - manual calculation needed

---

## Usage in Other Modules

Other Xoodoo modules use this package like this:

```vhdl
library work;
use work.xoodoo_globals.all;

entity some_module is
    port (
        state_in : in x_state_type;
        state_out : out x_state_type
    );
end entity;
```

They can then:
- Use `x_state_type` for state signals
- Access state elements as `state(1)(2)(15)`
- Use conversion functions when needed
- Use `ZERO_STATE` for initialization
- Check `active_rst` for reset conditions

---

## Conversion to Pure Verilog (.v)

Since Verilog doesn't have packages or 3D arrays easily, we need to:

1. **Remove the package** - functions go into utility modules
2. **Remove typedefs** - use raw `[383:0]` bit vectors
3. **Manual indexing** - access as `state[128*y + 32*x + i]`
4. **Conversion functions** - mostly pass-through in Verilog (same representation)

The Verilog version would look like:
```verilog
// No package - just use [383:0] directly
wire [383:0] state_in, state_out;

// Access bit at plane y, word x, bit i:
assign some_bit = state_in[128*y + 32*x + i];

// Zero state is just:
wire [383:0] ZERO_STATE = 384'b0;
```

---

## Summary

This package provides:
- ✅ **Type safety** for Xoodoo state (prevents wrong bit widths)
- ✅ **Clean syntax** for accessing state elements `state(y)(x)(i)`
- ✅ **Conversion utilities** between array and vector representations
- ✅ **Shared constants** used across all Xoodoo modules
- ✅ **Centralized definitions** - change state structure in one place

It's a fundamental building block that all other Xoodoo modules depend on!

