# CryptoCore FSM (Finite State Machine) Documentation

## Overview
The CryptoCore implements a unified FSM that handles AEAD encryption, AEAD decryption, and hash modes. The FSM behavior is controlled by `sel_type_s` which selects the operation mode.

## FSM States (15 states total)

| State | Value | Description |
|-------|-------|-------------|
| `IDLE` | 5'h0 | Initial state, waiting for input |
| `STORE_KEY` | 5'h1 | Loading key into Xoodoo state |
| `ABSORB_NONCE` | 5'h2 | Loading nonce (NPUB) into state |
| `PADD_NONCE` | 5'h3 | Padding nonce and starting first permutation |
| `ABSORB_AD` | 5'h4 | Absorbing associated data (AD) |
| `PADD_AD` | 5'h5 | Padding AD and starting permutation |
| `PADD_AD_ONLY_DOMAIN` | 5'h6 | Padding AD with domain only (partial block) |
| `PADD_AD_BLOCK` | 5'h7 | Padding AD for full block |
| `ABSORB_MSG` | 5'h8 | Absorbing message (plaintext/ciphertext) |
| `PADD_MSG` | 5'h9 | Padding message and starting permutation |
| `PADD_MSG_ONLY_DOMAIN` | 5'hA | Padding message with domain only |
| `PADD_MSG_BLOCK` | 5'hB | Padding message for full block |
| `EXTRACT_TAG` | 5'hC | Extracting authentication tag (encoder/hash) |
| `VERIFY_TAG` | 5'hD | Verifying authentication tag (decoder) |
| `WAIT_ACK` | 5'hE | Waiting for acknowledgment (decoder) |

## FSM Architecture

The FSM consists of **three main processes**:

### 1. State Register (Sequential)
- Updates `state_s` from `n_state_s` on clock edge
- Handles reset and state transitions

### 2. Next State Logic (Combinational)
- Determines `n_state_s` based on current state and inputs
- Implements state transition logic

### 3. Control Logic (Combinational)
- Generates control signals for current state
- Handles encoder/decoder differences

## State Flow Diagram

### AEAD Encoder Flow:
```
IDLE → STORE_KEY → ABSORB_NONCE → PADD_NONCE → ABSORB_AD → PADD_AD
                                                                    ↓
ABSORB_MSG ← PADD_MSG_BLOCK ← ABSORB_MSG ← PADD_AD_BLOCK ← ABSORB_AD
     ↓
PADD_MSG → EXTRACT_TAG → IDLE
```

### AEAD Decoder Flow:
```
IDLE → STORE_KEY → ABSORB_NONCE → PADD_NONCE → ABSORB_AD → PADD_AD
                                                                    ↓
ABSORB_MSG ← PADD_MSG_BLOCK ← ABSORB_MSG ← PADD_AD_BLOCK ← ABSORB_AD
     ↓
PADD_MSG → VERIFY_TAG → WAIT_ACK → IDLE
```

### Hash Mode Flow:
```
IDLE → STORE_KEY (skip) → ABSORB_AD → PADD_AD → ABSORB_MSG → PADD_MSG → EXTRACT_TAG → IDLE
```

## Key State Transitions

### Initialization Phase:
- **IDLE**: Waits for `key_valid` or `bdi_valid` → goes to `STORE_KEY`
- **STORE_KEY**: 
  - Hash mode: Skip to `ABSORB_AD`
  - AEAD mode: Load key, then go to `ABSORB_NONCE` when key complete
- **ABSORB_NONCE**: Load nonce (NPUB), go to `PADD_NONCE` when complete
- **PADD_NONCE**: Add padding, start Xoodoo permutation, go to `ABSORB_AD`

### Associated Data Phase:
- **ABSORB_AD**: Absorb AD word-by-word
  - If empty AD and empty message → `PADD_AD`
  - If PT/CT detected → `PADD_AD`
  - If end of transaction → `PADD_AD` or `PADD_AD_ONLY_DOMAIN`
  - If block full → `PADD_AD_BLOCK`
- **PADD_AD**: Add padding, start permutation → `ABSORB_MSG` or `PADD_MSG` (if empty msg)
- **PADD_AD_BLOCK**: Add padding for full block → back to `ABSORB_AD`
- **PADD_AD_ONLY_DOMAIN**: Add domain only → `ABSORB_MSG` or `PADD_MSG`

### Message Phase:
- **ABSORB_MSG**: Absorb message (PT for encoder, CT for decoder)
  - If end of transaction → `PADD_MSG` or `PADD_MSG_ONLY_DOMAIN`
  - If block full → `PADD_MSG_BLOCK`
- **PADD_MSG**: Add padding, start permutation
  - Encoder → `EXTRACT_TAG`
  - Decoder → `VERIFY_TAG`
  - Hash → `EXTRACT_TAG`
- **PADD_MSG_BLOCK**: Add padding for full block → back to `ABSORB_MSG`
- **PADD_MSG_ONLY_DOMAIN**: Add domain only → `EXTRACT_TAG` or `VERIFY_TAG`

### Tag Phase:
- **EXTRACT_TAG**: Read tag from Xoodoo state (encoder/hash)
  - When tag complete → `IDLE`
- **VERIFY_TAG**: Compare received tag with computed tag (decoder)
  - When verification complete → `WAIT_ACK`
- **WAIT_ACK**: Wait for acknowledgment (decoder) → `IDLE`

## Encoder vs Decoder Differences

### In ABSORB_MSG State:
- **Encoder**: Processes `HDR_PT` (plaintext)
  ```verilog
  word_in_s = padd(bdi_s, bdi_valid_bytes_s, bdi_pad_loc_s);
  ```
- **Decoder**: Processes `HDR_CT` (ciphertext), decrypts by XORing with Xoodoo state
  ```verilog
  word_in_s = (xoodoo_state_word_s & ~select_bytes(...)) ^ padd(...);
  ```

### After PADD_MSG:
- **Encoder**: Goes to `EXTRACT_TAG` to output tag
- **Decoder**: Goes to `VERIFY_TAG` to verify received tag

## Mode Selection

The FSM behavior is controlled by `sel_type_s`:
- `MODE_AEAD_ENC (3'b001)`: Encoder mode
- `MODE_AEAD_DEC (3'b010)`: Decoder mode  
- `MODE_HASH (3'b011)`: Hash mode
- `MODE_INIT (3'b000)`: Initialization
- `MODE_FINAL (3'b100)`: Finalization

## Domain Separation

Different domains are used for different operations:
- `DOMAIN_ABSORB_KEY`: Key absorption
- `DOMAIN_ABSORB`: After nonce
- `DOMAIN_ABSORB_HASH`: Hash mode
- `DOMAIN_CRYPT`: Encryption/decryption (XORed with AD domain)
- `DOMAIN_SQUEEZE`: Tag extraction
- `DOMAIN_ZERO`: Reset domain

## Notes

- The FSM waits for `xoodoo_valid_s` (permutation complete) before proceeding in many states
- Word counter (`word_cnt_s`) tracks progress through blocks
- Partial word handling via `bdi_partial_s` and `bdi_valid_bytes`
- The FSM supports streaming data (doesn't require full blocks)

