//--------------------------------------------------------------------------------
// @file       tb_CryptoCore.v
// @brief      Testbench for CryptoCore module (Xoodyak AEAD)
//--------------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_CryptoCore;

    // Parameters
    parameter CCW = 32;
    parameter CCSW = 32;
    parameter CCWdiv8 = CCW/8;
    parameter KEY_SIZE = 128;
    parameter NPUB_SIZE = 128;
    parameter TAG_SIZE = 128;
    
    // Header type constants
    localparam [3:0] HDR_AD = 4'h1;
    localparam [3:0] HDR_NPUB = 4'hD;
    localparam [3:0] HDR_PT = 4'h4;
    localparam [3:0] HDR_CT = 4'h5;
    localparam [3:0] HDR_TAG = 4'h8;
    
    // Test vectors (example values - replace with actual test vectors)
    reg [KEY_SIZE-1:0] test_key;
    reg [NPUB_SIZE-1:0] test_npub;
    reg [31:0] test_ad [0:3];  // 4 words of AD
    reg [31:0] test_pt [0:3];  // 4 words of plaintext
    reg [31:0] expected_ct [0:3];  // Expected ciphertext
    reg [31:0] expected_tag [0:3];  // Expected tag
    
    // Clock and reset
    reg clk;
    reg rst;
    
    // DUT signals
    reg [CCSW-1:0] key;
    reg key_valid;
    wire key_ready;
    reg [CCW-1:0] bdi;
    reg bdi_valid;
    wire bdi_ready;
    reg [CCWdiv8-1:0] bdi_pad_loc;
    reg [CCWdiv8-1:0] bdi_valid_bytes;
    reg [2:0] bdi_size;
    reg bdi_eot;
    reg bdi_eoi;
    reg [3:0] bdi_type;
    reg decrypt_in;
    reg key_update;
    
    wire [CCW-1:0] bdo;
    wire bdo_valid;
    reg bdo_ready;
    wire [3:0] bdo_type;
    wire [CCWdiv8-1:0] bdo_valid_bytes;
    wire end_of_block;
    wire msg_auth_valid;
    reg msg_auth_ready;
    wire msg_auth;
    
    // Test control
    integer test_count;
    integer pass_count;
    integer fail_count;
    integer i;
    
    // Storage for encryption results (used in decryption test)
    reg [CCW-1:0] received_ct [0:3];
    reg [CCW-1:0] received_tag [0:3];
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100MHz clock
    end
    
    // Instantiate DUT
    CryptoCore #(
        .roundsPerCycle(1)
    ) dut (
        .clk(clk),
        .rst(rst),
        .key(key),
        .key_valid(key_valid),
        .key_ready(key_ready),
        .bdi(bdi),
        .bdi_valid(bdi_valid),
        .bdi_ready(bdi_ready),
        .bdi_pad_loc(bdi_pad_loc),
        .bdi_valid_bytes(bdi_valid_bytes),
        .bdi_size(bdi_size),
        .bdi_eot(bdi_eot),
        .bdi_eoi(bdi_eoi),
        .bdi_type(bdi_type),
        .decrypt_in(decrypt_in),
        .key_update(key_update),
        .bdo(bdo),
        .bdo_valid(bdo_valid),
        .bdo_ready(bdo_ready),
        .bdo_type(bdo_type),
        .bdo_valid_bytes(bdo_valid_bytes),
        .end_of_block(end_of_block),
        .msg_auth_valid(msg_auth_valid),
        .msg_auth_ready(msg_auth_ready),
        .msg_auth(msg_auth)
    );
    
    // Task to send key
    task send_key;
        input [KEY_SIZE-1:0] key_data;
        integer idx;
        begin
            key_update = 1'b1;
            for (idx = 0; idx < KEY_SIZE/CCSW; idx = idx + 1) begin
                @(posedge clk);
                key = key_data[CCSW*idx +: CCSW];
                key_valid = 1'b1;
                wait(key_ready);
                @(posedge clk);
                key_valid = 1'b0;
            end
            key_update = 1'b0;
        end
    endtask
    
    // Task to send data word
    task send_word;
        input [CCW-1:0] data;
        input [3:0] type_val;
        input [CCWdiv8-1:0] valid_bytes;
        input eot_val;
        input eoi_val;
        begin
            @(posedge clk);
            bdi = data;
            bdi_type = type_val;
            bdi_valid_bytes = valid_bytes;
            bdi_pad_loc = {CCWdiv8{1'b0}};
            bdi_eot = eot_val;
            bdi_eoi = eoi_val;
            bdi_valid = 1'b1;
            @(posedge clk);
            while (!bdi_ready) @(posedge clk);
            @(posedge clk);
            bdi_valid = 1'b0;
        end
    endtask
    
    // Task to receive data word
    task receive_word;
        output [CCW-1:0] data;
        begin
            bdo_ready = 1'b1;
            @(posedge clk);
            while (!bdo_valid) @(posedge clk);
            data = bdo;
            @(posedge clk);
            bdo_ready = 1'b0;
        end
    endtask
    
    // Test: Encryption
    task test_encryption;
        integer idx;
        begin
            $display("=== Test %0d: Encryption ===", test_count);
            test_count = test_count + 1;
            
            // Initialize test vectors (example - replace with actual vectors)
            test_key = 128'h000102030405060708090A0B0C0D0E0F;
            test_npub = 128'h101112131415161718191A1B1C1D1E;
            test_ad[0] = 32'h20212223;
            test_ad[1] = 32'h24252627;
            test_ad[2] = 32'h28292A2B;
            test_ad[3] = 32'h2C2D2E2F;
            test_pt[0] = 32'h30313233;
            test_pt[1] = 32'h34353637;
            test_pt[2] = 32'h38393A3B;
            test_pt[3] = 32'h3C3D3E3F;
            
            // Reset
            rst = 1'b1;
            decrypt_in = 1'b0;
            key_valid = 1'b0;
            bdi_valid = 1'b0;
            bdo_ready = 1'b0;
            msg_auth_ready = 1'b0;
            #100;
            rst = 1'b0;
            #50;
            
            // Send key
            $display("Sending key...");
            send_key(test_key);
            #500;  // Wait for xoodoo to process key (12 cycles + overhead)
            
            // Send nonce
            $display("Sending nonce...");
            for (idx = 0; idx < NPUB_SIZE/CCW; idx = idx + 1) begin
                send_word(test_npub[CCW*idx +: CCW], 
                         HDR_NPUB, 
                         {CCWdiv8{1'b1}}, 
                         (idx == NPUB_SIZE/CCW - 1) ? 1'b1 : 1'b0,
                         1'b0);
            end
            #1000;  // Wait for xoodoo to process nonce padding (12 cycles + overhead)
            
            // Send AD
            $display("Sending AD...");
            for (idx = 0; idx < 4; idx = idx + 1) begin
                send_word(test_ad[idx], 
                         HDR_AD, 
                         {CCWdiv8{1'b1}}, 
                         (idx == 3) ? 1'b1 : 1'b0,
                         1'b0);
                // Wait for xoodoo processing after each AD word
                #200;  // Allow time for xoodoo to process if needed
            end
            #1000;  // Wait for xoodoo to process AD (12 cycles + overhead)
            
            // Send plaintext and receive ciphertext
            $display("Sending plaintext and receiving ciphertext...");
            for (idx = 0; idx < 4; idx = idx + 1) begin
                send_word(test_pt[idx], 
                         HDR_PT, 
                         {CCWdiv8{1'b1}}, 
                         (idx == 3) ? 1'b1 : 1'b0,
                         1'b0);
                // Wait for xoodoo processing (12 cycles per permutation)
                #500;
                // Receive ciphertext
                receive_word(received_ct[idx]);
                $display("  PT[%0d] = %h, CT[%0d] = %h", idx, test_pt[idx], idx, received_ct[idx]);
            end
            #1000;  // Wait for message padding and xoodoo (12 cycles + overhead)
            
            // Receive tag
            $display("Receiving tag...");
            for (idx = 0; idx < TAG_SIZE/CCW; idx = idx + 1) begin
                receive_word(received_tag[idx]);
                $display("  TAG[%0d] = %h", idx, received_tag[idx]);
            end
            
            $display("Encryption test completed.\n");
            #100;
        end
    endtask
    
    // Test: Decryption
    task test_decryption;
        integer idx;
        reg [CCW-1:0] received_pt [0:3];
        begin
            $display("=== Test %0d: Decryption ===", test_count);
            test_count = test_count + 1;
            
            // Reset
            rst = 1'b1;
            decrypt_in = 1'b1;
            key_valid = 1'b0;
            bdi_valid = 1'b0;
            bdo_ready = 1'b0;
            msg_auth_ready = 1'b0;
            #100;
            rst = 1'b0;
            #50;
            
            // Send key
            $display("Sending key...");
            send_key(test_key);
            #500;  // Wait for xoodoo to process key (12 cycles + overhead)
            
            // Send nonce
            $display("Sending nonce...");
            for (idx = 0; idx < NPUB_SIZE/CCW; idx = idx + 1) begin
                send_word(test_npub[CCW*idx +: CCW], 
                         HDR_NPUB, 
                         {CCWdiv8{1'b1}}, 
                         (idx == NPUB_SIZE/CCW - 1) ? 1'b1 : 1'b0,
                         1'b0);
            end
            #1000;  // Wait for xoodoo to process nonce padding (12 cycles + overhead)
            
            // Send AD
            $display("Sending AD...");
            for (idx = 0; idx < 4; idx = idx + 1) begin
                send_word(test_ad[idx], 
                         HDR_AD, 
                         {CCWdiv8{1'b1}}, 
                         (idx == 3) ? 1'b1 : 1'b0,
                         1'b0);
            end
            #1000;  // Wait for xoodoo to process AD (12 cycles + overhead)
            
            // Send ciphertext and receive plaintext
            $display("Sending ciphertext and receiving plaintext...");
            for (idx = 0; idx < 4; idx = idx + 1) begin
                send_word(received_ct[idx], 
                         HDR_CT, 
                         {CCWdiv8{1'b1}}, 
                         (idx == 3) ? 1'b1 : 1'b0,
                         1'b0);
                // Wait for xoodoo processing (12 cycles per permutation)
                #500;
                // Receive plaintext
                receive_word(received_pt[idx]);
                $display("  CT[%0d] = %h, PT[%0d] = %h", idx, received_ct[idx], idx, received_pt[idx]);
                
                // Verify plaintext
                if (received_pt[idx] != test_pt[idx]) begin
                    $display("ERROR: PT[%0d] mismatch! Expected %h, got %h", idx, test_pt[idx], received_pt[idx]);
                    fail_count = fail_count + 1;
                end
            end
            #1000;  // Wait for message padding and xoodoo (12 cycles + overhead)
            
            // Send tag for verification
            $display("Sending tag for verification...");
            for (idx = 0; idx < TAG_SIZE/CCW; idx = idx + 1) begin
                send_word(received_tag[idx], 
                         HDR_TAG, 
                         {CCWdiv8{1'b1}}, 
                         (idx == TAG_SIZE/CCW - 1) ? 1'b1 : 1'b0,
                         1'b0);
            end
            #1000;  // Wait for tag verification (12 cycles + overhead)
            
            // Wait for msg_auth
            @(posedge clk);
            msg_auth_ready = 1'b1;
            wait(msg_auth_valid);
            @(posedge clk);
            msg_auth_ready = 1'b0;
            
            if (msg_auth) begin
                $display("Tag verification PASSED");
                pass_count = pass_count + 1;
            end else begin
                $display("Tag verification FAILED");
                fail_count = fail_count + 1;
            end
            
            $display("Decryption test completed.\n");
        end
    endtask
    
    // Main test sequence
    initial begin
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        $display("========================================");
        $display("CryptoCore Testbench Starting");
        $display("========================================\n");
        
        // Run encryption test
        test_encryption;
        #100;
        
        // Run decryption test
        test_decryption;
        #100;
        
        // Summary
        $display("========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total tests: %0d", test_count);
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        $display("========================================");
        
        if (fail_count == 0) begin
            $display("All tests PASSED!");
        end else begin
            $display("Some tests FAILED!");
        end
        
        #100;
        $finish;
    end
    
    // Monitor for debugging
    initial begin
        $monitor("Time=%0t: key_ready=%b, bdi_ready=%b, bdo_valid=%b, bdo_type=%h, msg_auth=%b",
                 $time, key_ready, bdi_ready, bdo_valid, bdo_type, msg_auth);
    end

endmodule

