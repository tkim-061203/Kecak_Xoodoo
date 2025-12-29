//--------------------------------------------------------------------------------
// @file       CryptoCore.v
// @brief      Implementation of the xoodyak cipher (encoder/decoder only, no hash).
//
// @license    To the extent possible under law, the implementer has waived all copyright
//             and related or neighboring rights to the source code in this file.
//             http://creativecommons.org/publicdomain/zero/1.0/
// @note       This code is based on the package for the dummy cipher provided within
//             the Development Package for Hardware Implementations Compliant with
//             the Hardware API for Lightweight Cryptography (https://github.com/GMUCERG/LWC)
//--------------------------------------------------------------------------------

`timescale 1ns/1ps

module CryptoCore(
    clk,
    rst,
    //--!key----------------------------------------------------
    key,
    key_valid,
    key_ready,
    //--!Data----------------------------------------------------
    bdi,
    bdi_valid,
    bdi_ready,
    bdi_pad_loc,
    bdi_valid_bytes,
    bdi_size,
    bdi_eot,
    bdi_eoi,
    bdi_type,
    decrypt_in,
    key_update,
    sel_type
);

    // Parameters
    parameter roundsPerCycle = 2;
    parameter active_rst_p = 1'b1;
    
    // Design parameters
    parameter TAG_SIZE = 128;
    parameter CCW = 32;
    parameter CCSW = 32;
    parameter CCWdiv8 = CCW/8;
    parameter NPUB_SIZE = 128;
    parameter DBLK_SIZE = 352;
    parameter KEY_SIZE = 128;
    parameter STATE_SIZE = 384;
    parameter RKIN = 352;
    parameter RKOUT = 192;
    
    // Constants
    localparam STATE_WORDS_C = (STATE_SIZE + CCW - 1) / CCW;
    localparam NPUB_WORDS_C = (NPUB_SIZE + CCW - 1) / CCW;
    localparam BLOCK_WORDS_C = (DBLK_SIZE + CCW - 1) / CCW;
    localparam RKIN_WORDS_C = (RKIN + CCW - 1) / CCW;
    localparam RKOUT_WORDS_C = (RKOUT + CCW - 1) / CCW;
    localparam KEY_WORDS_C = (KEY_SIZE + CCW - 1) / CCW;
    localparam TAG_WORDS_C = (TAG_SIZE + CCW - 1) / CCW;
    
    // Domain constants
    localparam [7:0] CMD_01 = 8'h01;
    localparam [7:0] CMD_ZERO = 8'h00;
    localparam [7:0] CMD_ABSORB_KEY = 8'h02;
    localparam [7:0] CMD_ABSORB = 8'h03;
    localparam [7:0] CMD_RATCHET = 8'h10;
    localparam [7:0] CMD_SQUEEZE = 8'h40;
    localparam [7:0] CMD_CRYPT = 8'h80;
    
    localparam [CCW-1:0] PADD_01 = {24'h0, 8'h01};
    localparam [CCW-1:0] PADD_01_KEY = {16'h0, 8'h01, 8'h0};
    localparam [CCW-1:0] PADD_01_KEY_NONCE = {16'h0, 1'b1, 3'h0, 1'b1, 4'h0};
    
    localparam [CCW-1:0] DOMAIN_ABSORB_HASH = {24'h0, CMD_01};
    localparam [CCW-1:0] DOMAIN_ZERO = {24'h0, CMD_ZERO};
    localparam [CCW-1:0] DOMAIN_ABSORB_KEY = {24'h0, CMD_ABSORB_KEY};
    localparam [CCW-1:0] DOMAIN_ABSORB = {24'h0, CMD_ABSORB};
    localparam [CCW-1:0] DOMAIN_RATCHET = {24'h0, CMD_RATCHET};
    localparam [CCW-1:0] DOMAIN_SQUEEZE = {24'h0, CMD_SQUEEZE};
    localparam [CCW-1:0] DOMAIN_CRYPT = {24'h0, CMD_CRYPT};
    
    // Header type constants
    localparam [3:0] HDR_AD = 4'h1;
    localparam [3:0] HDR_NPUB_AD = 4'h2;
    localparam [3:0] HDR_AD_NPUB = 4'h3;
    localparam [3:0] HDR_PT = 4'h4;
    localparam [3:0] HDR_CT = 4'h5;
    localparam [3:0] HDR_CT_TAG = 4'h6;
    localparam [3:0] HDR_TAG = 4'h8;
    localparam [3:0] HDR_KEY = 4'hC;
    localparam [3:0] HDR_NPUB = 4'hD;
    
    // Mode selection constants
    localparam [2:0] MODE_INIT = 3'b000;
    localparam [2:0] MODE_AEAD_ENC = 3'b001;      // AEAD encoder
    localparam [2:0] MODE_AEAD_DEC = 3'b010;      // AEAD decoder
    localparam [2:0] MODE_HASH = 3'b011;
    localparam [2:0] MODE_FINAL = 3'b100;
    
    // Port declarations
    input               clk;
    input               rst;
    input  [CCSW-1:0]   key;
    input               key_valid;
    output reg          key_ready;
    input  [CCW-1:0]    bdi;
    input               bdi_valid;
    output reg          bdi_ready;
    input  [CCWdiv8-1:0] bdi_pad_loc;
    input  [CCWdiv8-1:0] bdi_valid_bytes;
    input  [2:0]        bdi_size;
    input               bdi_eot;
    input               bdi_eoi;
    input  [3:0]        bdi_type;
    input               decrypt_in;
    input               key_update;
    input  [2:0]        sel_type;        // Mode selection: 000=init, 001=AEAD encoder, 010=AEAD decoder, 011=hash, 100=final
    
    // State machine type - 15 states total
    // Phase 1: Initialization (IDLE, STORE_KEY, ABSORB_NONCE, PADD_NONCE)
    // Phase 2: Associated Data (ABSORB_AD, PADD_AD, PADD_AD_ONLY_DOMAIN, PADD_AD_BLOCK)
    // Phase 3: Message Processing (ABSORB_MSG, PADD_MSG, PADD_MSG_ONLY_DOMAIN, PADD_MSG_BLOCK)
    // Phase 4: Tag Handling (EXTRACT_TAG for encoder, VERIFY_TAG for decoder, WAIT_ACK)
    localparam [4:0] IDLE = 5'h0,                    // Initial/waiting state
                     STORE_KEY = 5'h1,               // Load key into state
                     ABSORB_NONCE = 5'h2,            // Load nonce (NPUB)
                     PADD_NONCE = 5'h3,              // Pad nonce, start permutation
                     ABSORB_AD = 5'h4,               // Absorb associated data
                     PADD_AD = 5'h5,                 // Pad AD, start permutation
                     PADD_AD_ONLY_DOMAIN = 5'h6,     // Pad AD with domain only (partial)
                     PADD_AD_BLOCK = 5'h7,           // Pad AD for full block
                     ABSORB_MSG = 5'h8,              // Absorb message (PT/CT)
                     PADD_MSG = 5'h9,                // Pad message, start permutation
                     PADD_MSG_ONLY_DOMAIN = 5'hA,    // Pad message with domain only
                     PADD_MSG_BLOCK = 5'hB,          // Pad message for full block
                     EXTRACT_TAG = 5'hC,             // Extract tag (encoder/hash)
                     VERIFY_TAG = 5'hD,              // Verify tag (decoder)
                     WAIT_ACK = 5'hE;                // Wait for ack (decoder)
    
    // Internal signals
    reg [4:0] state_s, n_state_s;
    reg [4:0] word_cnt_s;
    
    // Internal Port signals
    reg [CCSW-1:0] key_s;
    reg            key_ready_s;
    reg            bdi_ready_s;
    reg [CCW-1:0]  bdi_s;
    reg [CCWdiv8-1:0] bdi_valid_bytes_s;
    reg [CCWdiv8-1:0] bdi_pad_loc_s;
    
    reg            tag_ready_s;
    
    // Internal flags
    reg            bdi_partial_s;
    wire           decrypt_s;  // Derived from sel_type_s: 1 for AEAD decoder, 0 otherwise
    reg            n_eoi_s, eoi_s;
    reg            n_update_key_s, update_key_s;
    reg            n_first_block_s, first_block_s;
    reg [2:0]      sel_type_s, n_sel_type_s;
    
    // Xoodoo signals
    reg            xoodoo_start_s, n_xoodoo_start_s;
    wire           xoodoo_valid_s;
    reg [31:0]     word_in_s;
    wire [3:0]     word_index_in_s;
    reg            word_enable_in_s;
    reg            init_reg_s;
    reg [31:0]     padd_s;
    reg            padd_enable_s;
    wire [31:0]    xoodoo_state_word_s;
    
    // Xoodyak signals
    reg [CCW-1:0]  domain_s, n_domain_s;
    
    // Xoodoo component instantiation
    xoodoo #(.roundPerCycle(roundsPerCycle)) i_xoodoo(
        .clk_i(clk),
        .rst_i(rst),
        .start_i(xoodoo_start_s),
        .state_valid_o(xoodoo_valid_s),
        .init_reg(init_reg_s),
        .word_in(word_in_s),
        .word_index_in(word_index_in_s),
        .word_enable_in(word_enable_in_s),
        .domain_i(padd_s),
        .domain_enable_i(padd_enable_s),
        .word_out(xoodoo_state_word_s)
    );
    
    assign word_index_in_s = word_cnt_s;
    
    // Decrypt signal derived from sel_type: 1 for AEAD decoder, 0 otherwise
    assign decrypt_s = (sel_type_s == MODE_AEAD_DEC);
    
    // I/O Mappings (big endian)
    always @(*) begin
        key_s = key;
        bdi_s = bdi;
        bdi_valid_bytes_s = bdi_valid_bytes;
        bdi_pad_loc_s = bdi_pad_loc;
        key_ready = key_ready_s;
        bdi_ready = bdi_ready_s;
    end
    
    // Utility signal: Indicates whether the input word is fully filled or not
    always @(*) begin
        bdi_partial_s = |bdi_pad_loc_s;
    end
    
    // Helper function: padd
    function [CCW-1:0] padd;
        input [CCW-1:0] bdi_val;
        input [CCWdiv8-1:0] bdi_valid_bytes_val;
        input [CCWdiv8-1:0] bdi_pad_loc_val;
        begin
            padd = {CCW{1'b0}};
            if (bdi_valid_bytes_val[0]) begin
                padd[7:0] = bdi_val[7:0];
            end else if (bdi_pad_loc_val[0]) begin
                padd[7:0] = 8'h01;
            end
            if (bdi_valid_bytes_val[1]) begin
                padd[15:8] = bdi_val[15:8];
            end else if (bdi_pad_loc_val[1]) begin
                padd[15:8] = 8'h01;
            end
            if (bdi_valid_bytes_val[2]) begin
                padd[23:16] = bdi_val[23:16];
            end else if (bdi_pad_loc_val[2]) begin
                padd[23:16] = 8'h01;
            end
            if (bdi_valid_bytes_val[3]) begin
                padd[31:24] = bdi_val[31:24];
            end else if (bdi_pad_loc_val[3]) begin
                padd[31:24] = 8'h01;
            end
        end
    endfunction
    
    // Helper function: select_bytes
    function [CCW-1:0] select_bytes;
        input [CCW-1:0] bdi_val;
        input [CCWdiv8-1:0] bdi_valid_bytes_val;
        begin
            select_bytes = {CCW{1'b0}};
            if (bdi_valid_bytes_val[0]) begin
                select_bytes[7:0] = 8'h00;
            end else begin
                select_bytes[7:0] = 8'hFF;
            end
            if (bdi_valid_bytes_val[1]) begin
                select_bytes[15:8] = 8'h00;
            end else begin
                select_bytes[15:8] = 8'hFF;
            end
            if (bdi_valid_bytes_val[2]) begin
                select_bytes[23:16] = 8'h00;
            end else begin
                select_bytes[23:16] = 8'hFF;
            end
            if (bdi_valid_bytes_val[3]) begin
                select_bytes[31:24] = 8'h00;
            end else begin
                select_bytes[31:24] = 8'hFF;
            end
        end
    endfunction
    
    // Registers for state and internal signals
    always @(posedge clk) begin
        if (rst == active_rst_p) begin
            eoi_s <= 1'b0;
            update_key_s <= 1'b0;
            state_s <= IDLE;
            first_block_s <= 1'b1;
            domain_s <= {CCW{1'b0}};
            xoodoo_start_s <= 1'b0;
            sel_type_s <= MODE_INIT;
        end else begin
            eoi_s <= n_eoi_s;
            update_key_s <= n_update_key_s;
            state_s <= n_state_s;
            first_block_s <= n_first_block_s;
            domain_s <= n_domain_s;
            xoodoo_start_s <= n_xoodoo_start_s;
            sel_type_s <= n_sel_type_s;
        end
    end
    
    // Next_state FSM - Unified FSM for both encoder and decoder modes
    // The FSM behavior differs based on sel_type_s:
    //   - MODE_AEAD_ENC (3'b001): Encoder mode - encrypts plaintext, extracts tag
    //   - MODE_AEAD_DEC (3'b010): Decoder mode - decrypts ciphertext, verifies tag
    //   - MODE_HASH (3'b011): Hash mode - processes data for hashing
    always @(*) begin
        n_state_s = state_s;
        
        case (state_s)
            IDLE: begin
                if (key_valid || bdi_valid) begin
                    n_state_s = STORE_KEY;
                end else begin
                    n_state_s = IDLE;
                end
            end
            
            STORE_KEY: begin
                // For hash mode, skip key and nonce, go directly to data absorption
                if (sel_type_s == MODE_HASH) begin
                    n_state_s = ABSORB_AD;
                end else if (((key_valid && key_ready_s) || !key_update) && 
                    (word_cnt_s >= KEY_WORDS_C - 1)) begin
                    // For AEAD modes, absorb nonce after key
                    n_state_s = ABSORB_NONCE;
                end else begin
                    n_state_s = STORE_KEY;
                end
            end
            
            ABSORB_NONCE: begin
                // Only for AEAD modes (skip for hash)
                if (sel_type_s == MODE_HASH) begin
                    n_state_s = ABSORB_AD;
                end else if (bdi_valid && bdi_ready_s && 
                    (word_cnt_s >= KEY_WORDS_C + NPUB_WORDS_C - 1)) begin
                    n_state_s = PADD_NONCE;
                end else begin
                    n_state_s = ABSORB_NONCE;
                end
            end
            
            PADD_NONCE: begin
                n_state_s = ABSORB_AD;
            end
            
            ABSORB_AD: begin
                if (xoodoo_valid_s && !xoodoo_start_s) begin
                    if (eoi_s) begin // empty ad and empty msg
                        n_state_s = PADD_AD;
                    end else begin
                        if (bdi_valid && (bdi_type == HDR_PT || bdi_type == HDR_CT)) begin
                            n_state_s = PADD_AD;
                        end else if (bdi_valid && bdi_ready_s && bdi_eot) begin
                            if (word_cnt_s < RKIN_WORDS_C) begin
                                if (!bdi_partial_s) begin
                                    n_state_s = PADD_AD;
                                end else begin
                                    n_state_s = PADD_AD_ONLY_DOMAIN;
                                end
                            end else begin
                                n_state_s = PADD_AD;
                            end
                        end else if (bdi_valid && bdi_ready_s && 
                                   (word_cnt_s >= RKIN_WORDS_C - 1)) begin
                            n_state_s = PADD_AD_BLOCK;
                        end else begin
                            n_state_s = ABSORB_AD;
                        end
                    end
                end else begin
                    n_state_s = ABSORB_AD;
                end
            end
            
            PADD_AD: begin
                if (eoi_s) begin // empty msg
                    n_state_s = PADD_MSG;
                end else begin
                    n_state_s = ABSORB_MSG;
                end
            end
            
            PADD_AD_ONLY_DOMAIN: begin
                if (eoi_s) begin // empty msg
                    n_state_s = PADD_MSG;
                end else begin
                    n_state_s = ABSORB_MSG;
                end
            end
            
            PADD_AD_BLOCK: begin
                n_state_s = ABSORB_AD;
            end
            
            ABSORB_MSG: begin
                if (xoodoo_valid_s && !xoodoo_start_s) begin
                    if (bdi_valid && bdi_ready_s && bdi_eot) begin
                        if (word_cnt_s < RKOUT_WORDS_C) begin
                            if (!bdi_partial_s) begin
                                n_state_s = PADD_MSG;
                            end else begin
                                n_state_s = PADD_MSG_ONLY_DOMAIN;
                            end
                        end else begin
                            n_state_s = PADD_MSG;
                        end
                    end else if (bdi_valid && bdi_ready_s && 
                               (word_cnt_s >= RKOUT_WORDS_C - 1)) begin
                        n_state_s = PADD_MSG_BLOCK;
                    end else begin
                        n_state_s = ABSORB_MSG;
                    end
                end else begin
                    n_state_s = ABSORB_MSG;
                end
            end
            
            PADD_MSG: begin
                if (xoodoo_valid_s && !xoodoo_start_s) begin
                    // For AEAD decoder: verify tag, for AEAD encoder: extract tag
                    if (sel_type_s == MODE_AEAD_DEC) begin
                        n_state_s = VERIFY_TAG;
                    end else if (sel_type_s == MODE_AEAD_ENC) begin
                        n_state_s = EXTRACT_TAG;
                    end else begin
                        // For hash mode, go to EXTRACT_TAG (squeeze)
                        n_state_s = EXTRACT_TAG;
                    end
                end else begin
                    n_state_s = PADD_MSG;
                end
            end
            
            PADD_MSG_ONLY_DOMAIN: begin
                // For AEAD decoder: verify tag, for AEAD encoder: extract tag
                if (sel_type_s == MODE_AEAD_DEC) begin
                    n_state_s = VERIFY_TAG;
                end else if (sel_type_s == MODE_AEAD_ENC) begin
                    n_state_s = EXTRACT_TAG;
                end else begin
                    // For hash mode, go to EXTRACT_TAG (squeeze)
                    n_state_s = EXTRACT_TAG;
                end
            end
            
            PADD_MSG_BLOCK: begin
                n_state_s = ABSORB_MSG;
            end
            
            EXTRACT_TAG: begin
                if (xoodoo_valid_s && !xoodoo_start_s) begin
                    if (word_cnt_s >= TAG_WORDS_C - 1) begin
                        n_state_s = IDLE;
                    end else begin
                        n_state_s = EXTRACT_TAG;
                    end
                end else begin
                    n_state_s = EXTRACT_TAG;
                end
            end
            
            VERIFY_TAG: begin
                if (xoodoo_valid_s && !xoodoo_start_s) begin
                    if (bdi_valid && bdi_ready_s && (word_cnt_s >= TAG_WORDS_C - 1)) begin
                        n_state_s = WAIT_ACK;
                    end else begin
                        n_state_s = VERIFY_TAG;
                    end
                end else begin
                    n_state_s = VERIFY_TAG;
                end
            end
            
            WAIT_ACK: begin
                n_state_s = IDLE;
            end
            
            default: begin
                n_state_s = IDLE;
            end
        endcase
    end
    
    // Control logic process (decoder/encoder) - Generates control signals for current state
    // This process handles both encoder and decoder modes based on sel_type_s
    // Encoder: Processes HDR_PT (plaintext), outputs ciphertext, extracts tag
    // Decoder: Processes HDR_CT (ciphertext), outputs plaintext, verifies tag
    always @(*) begin
        // Default values
        key_ready_s = 1'b0;
        bdi_ready_s = 1'b0;
        n_eoi_s = eoi_s;
        n_update_key_s = update_key_s;
        n_first_block_s = first_block_s;
        n_domain_s = domain_s;
        n_sel_type_s = sel_type_s;
        tag_ready_s = 1'b0;
        init_reg_s = 1'b0;
        word_in_s = {CCW{1'b0}};
        word_enable_in_s = 1'b0;
        padd_s = {CCW{1'b0}};
        padd_enable_s = 1'b0;
        n_xoodoo_start_s = 1'b0;
        
        case (state_s)
            IDLE: begin
                n_eoi_s = 1'b0;
                n_first_block_s = 1'b1;
                n_sel_type_s = sel_type;
                init_reg_s = 1'b1;
                // For hash mode, key_update might not be needed
                if (key_valid && key_update && (sel_type != MODE_HASH)) begin
                    n_update_key_s = 1'b1;
                end else if (sel_type == MODE_HASH) begin
                    // Hash mode doesn't require key, so we can proceed without key_update
                    n_update_key_s = 1'b0;
                end
            end
            
            STORE_KEY: begin
                // For hash mode, skip key storage and use hash domain
                if (sel_type_s == MODE_HASH) begin
                    // Hash mode - no key needed, use hash domain
                    n_domain_s = DOMAIN_ABSORB_HASH;
                end else begin
                    // For AEAD modes, store key
                    if (update_key_s) begin
                        key_ready_s = 1'b1;
                    end
                    if (key_valid && key_ready_s) begin
                        word_in_s = key_s;
                        word_enable_in_s = 1'b1;
                    end
                    n_domain_s = DOMAIN_ABSORB_KEY;
                end
            end
            
            ABSORB_NONCE: begin
                // Only for AEAD modes
                if (sel_type_s != MODE_HASH) begin
                    bdi_ready_s = 1'b1;
                    n_eoi_s = bdi_eoi;
                    if (bdi_valid && bdi_ready_s && (bdi_type == HDR_NPUB)) begin
                        word_in_s = bdi_s;
                        word_enable_in_s = 1'b1;
                        n_eoi_s = bdi_eoi;
                    end
                end
            end
            
            PADD_NONCE: begin
                // Only for AEAD modes
                if (sel_type_s != MODE_HASH) begin
                    word_in_s = PADD_01_KEY_NONCE;
                    word_enable_in_s = 1'b1;
                    padd_s = domain_s;
                    padd_enable_s = 1'b1;
                    n_xoodoo_start_s = 1'b1;
                    n_domain_s = DOMAIN_ABSORB;
                end
            end
            
            ABSORB_AD: begin
                if (!eoi_s) begin
                    // For hash mode, process all input as data
                    if (sel_type_s == MODE_HASH) begin
                        if (xoodoo_valid_s && !xoodoo_start_s) begin
                            bdi_ready_s = 1'b1;
                        end
                        if (bdi_valid && bdi_ready_s) begin
                            n_eoi_s = bdi_eoi;
                            word_in_s = padd(bdi_s, bdi_valid_bytes_s, bdi_pad_loc_s);
                            word_enable_in_s = 1'b1;
                        end
                    end else begin
                        // For AEAD modes, process AD
                        if (!(bdi_valid && (bdi_type == HDR_PT || bdi_type == HDR_CT))) begin
                            if (xoodoo_valid_s && !xoodoo_start_s) begin
                                bdi_ready_s = 1'b1;
                            end
                        end
                        if (bdi_valid && bdi_ready_s) begin
                            n_eoi_s = bdi_eoi;
                            if (bdi_type == HDR_AD) begin
                                word_in_s = padd(bdi_s, bdi_valid_bytes_s, bdi_pad_loc_s);
                                word_enable_in_s = 1'b1;
                            end
                        end
                    end
                end
            end
            
            PADD_AD: begin
                if (sel_type_s == MODE_HASH) begin
                    // Hash mode: use hash domain, no CRYPT domain
                    if (word_cnt_s < STATE_WORDS_C - 1) begin
                        word_in_s = PADD_01;
                        word_enable_in_s = 1'b1;
                        padd_s = domain_s;
                        padd_enable_s = 1'b1;
                    end else begin
                        padd_s = PADD_01 ^ domain_s;
                        padd_enable_s = 1'b1;
                    end
                    n_domain_s = DOMAIN_ZERO;
                end else begin
                    // AEAD mode: use CRYPT domain
                    if (word_cnt_s < STATE_WORDS_C - 1) begin
                        word_in_s = PADD_01;
                        word_enable_in_s = 1'b1;
                        padd_s = domain_s ^ DOMAIN_CRYPT;
                        padd_enable_s = 1'b1;
                    end else begin
                        padd_s = PADD_01 ^ domain_s ^ DOMAIN_CRYPT;
                        padd_enable_s = 1'b1;
                    end
                    n_domain_s = DOMAIN_ZERO;
                end
                n_xoodoo_start_s = 1'b1;
            end
            
            PADD_AD_ONLY_DOMAIN: begin
                if (sel_type_s == MODE_HASH) begin
                    // Hash mode: use hash domain
                    padd_s = domain_s;
                end else begin
                    // AEAD mode: use CRYPT domain
                    padd_s = domain_s ^ DOMAIN_CRYPT;
                end
                padd_enable_s = 1'b1;
                n_domain_s = DOMAIN_ZERO;
                n_xoodoo_start_s = 1'b1;
            end
            
            PADD_AD_BLOCK: begin
                padd_s = PADD_01 ^ domain_s;
                padd_enable_s = 1'b1;
                n_domain_s = DOMAIN_ZERO;
                n_xoodoo_start_s = 1'b1;
            end
            
            ABSORB_MSG: begin
                if (xoodoo_valid_s && !xoodoo_start_s) begin
                    bdi_ready_s = 1'b1;
                end
                if (bdi_valid && bdi_ready_s) begin
                    // AEAD encoder: process plaintext (HDR_PT)
                    if ((sel_type_s == MODE_AEAD_ENC) && (bdi_type == HDR_PT)) begin
                        word_in_s = padd(bdi_s, bdi_valid_bytes_s, bdi_pad_loc_s);
                        word_enable_in_s = 1'b1;
                    // AEAD decoder: process ciphertext (HDR_CT)
                    end else if ((sel_type_s == MODE_AEAD_DEC) && (bdi_type == HDR_CT)) begin
                        word_in_s = (xoodoo_state_word_s & ~select_bytes(bdi_s, bdi_valid_bytes_s)) ^ 
                                    padd(bdi_s, bdi_valid_bytes_s, bdi_pad_loc_s);
                        word_enable_in_s = 1'b1;
                    // Hash mode: process any input
                    end else if (sel_type_s == MODE_HASH) begin
                        word_in_s = padd(bdi_s, bdi_valid_bytes_s, bdi_pad_loc_s);
                        word_enable_in_s = 1'b1;
                    end
                end
            end
            
            PADD_MSG: begin
                if (xoodoo_valid_s && !xoodoo_start_s) begin
                    word_in_s = PADD_01;
                    word_enable_in_s = 1'b1;
                    n_xoodoo_start_s = 1'b1;
                    padd_s = DOMAIN_SQUEEZE;
                    padd_enable_s = 1'b1;
                end
            end
            
            PADD_MSG_ONLY_DOMAIN: begin
                n_xoodoo_start_s = 1'b1;
                padd_s = DOMAIN_SQUEEZE;
                padd_enable_s = 1'b1;
            end
            
            PADD_MSG_BLOCK: begin
                word_in_s = PADD_01;
                word_enable_in_s = 1'b1;
                n_xoodoo_start_s = 1'b1;
            end
            
            EXTRACT_TAG: begin
                if (xoodoo_valid_s && !xoodoo_start_s) begin
                    tag_ready_s = 1'b1;
                end
            end
            
            VERIFY_TAG: begin
                if (xoodoo_valid_s && !xoodoo_start_s) begin
                    bdi_ready_s = 1'b1;
                end
                if (bdi_valid && bdi_ready_s && (bdi_type == HDR_TAG)) begin
                    // Tag verification logic removed
                end
            end
            
            WAIT_ACK: begin
                // Wait for acknowledgment removed
            end
            
            default: begin
                // null
            end
        endcase
    end
    
    // Word, Byte and Block counters
    always @(posedge clk) begin
        case (state_s)
            IDLE: begin
                word_cnt_s <= 0;
            end
            
            STORE_KEY: begin
                // For hash mode, skip counting
                if (sel_type_s != MODE_HASH) begin
                    if (key_update) begin
                        if (key_valid && key_ready_s) begin
                            word_cnt_s <= word_cnt_s + 1;
                        end
                    end else begin
                        word_cnt_s <= word_cnt_s + 1;
                    end
                end else begin
                    word_cnt_s <= 0;
                end
            end
            
            ABSORB_NONCE: begin
                if (bdi_valid && bdi_ready_s) begin
                    if (word_cnt_s > NPUB_WORDS_C + KEY_WORDS_C - 1) begin
                        word_cnt_s <= 0;
                    end else begin
                        word_cnt_s <= word_cnt_s + 1;
                    end
                end
            end
            
            PADD_NONCE: begin
                word_cnt_s <= 0;
            end
            
            ABSORB_AD: begin
                if (bdi_valid && bdi_ready_s) begin
                    if ((word_cnt_s > RKIN_WORDS_C - 1) || 
                        (bdi_eot && bdi_partial_s)) begin
                        word_cnt_s <= 0;
                    end else begin
                        word_cnt_s <= word_cnt_s + 1;
                    end
                end
            end
            
            ABSORB_MSG: begin
                if (bdi_valid && bdi_ready_s) begin
                    if ((word_cnt_s > RKOUT_WORDS_C - 1) || 
                        (bdi_eot && bdi_partial_s)) begin
                        word_cnt_s <= 0;
                    end else begin
                        word_cnt_s <= word_cnt_s + 1;
                    end
                end
            end
            
            PADD_AD, PADD_MSG, PADD_AD_BLOCK, PADD_AD_ONLY_DOMAIN, 
            PADD_MSG_BLOCK, PADD_MSG_ONLY_DOMAIN: begin
                word_cnt_s <= 0;
            end
            
            EXTRACT_TAG: begin
                if (tag_ready_s) begin
                    if (word_cnt_s >= TAG_WORDS_C - 1) begin
                        word_cnt_s <= 0;
                    end else begin
                        word_cnt_s <= word_cnt_s + 1;
                    end
                end
            end
            
            VERIFY_TAG: begin
                if (bdi_valid && bdi_ready_s) begin
                    if (word_cnt_s >= TAG_WORDS_C - 1) begin
                        word_cnt_s <= 0;
                    end else begin
                        word_cnt_s <= word_cnt_s + 1;
                    end
                end
            end
            
            default: begin
                // null
            end
        endcase
    end

endmodule

