//--------------------------------------------------------------------------------
// Testbench for xoodoo.v - ModelSim compatible
// Tests Xoodoo permutation with word-by-word interface
//--------------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_xoodoo;
    // Testbench signals matching new xoodoo.v interface
    reg         clk_i;
    reg         rst_i;
    reg         start_i;
    wire        state_valid_o;
    reg         init_reg;
    reg  [31:0] word_in;
    reg  [3:0]  word_index_in;  // 0 to 11
    reg         word_enable_in;
    reg  [31:0] domain_i;
    reg         domain_enable_i;
    wire [31:0] word_out;
    
    // Test control signals
    integer i, j;
    integer iteration_count;
    reg [383:0] current_state;
    reg [383:0] expected_output;
    reg [383:0] expected_final;  // Expected output after 384 permutations
    reg test_complete;
    reg [31:0] state_words [0:11];  // Store state as 12 words
    
    // Instantiate the Device Under Test (DUT)
    xoodoo dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .start_i(start_i),
        .state_valid_o(state_valid_o),
        .init_reg(init_reg),
        .word_in(word_in),
        .word_index_in(word_index_in),
        .word_enable_in(word_enable_in),
        .domain_i(domain_i),
        .domain_enable_i(domain_enable_i),
        .word_out(word_out)
    );
    
    // Clock generation (100ns period = 10MHz)
    initial begin
        clk_i = 0;
        forever #50 clk_i = ~clk_i;
    end
    
    // Test procedure
    initial begin
        // Initialize all signals
        rst_i = 1'b1;  // Active high reset
        start_i = 1'b0;
        init_reg = 1'b0;
        word_in = 32'h0;
        word_index_in = 4'h0;
        word_enable_in = 1'b0;
        domain_i = 32'h0;
        domain_enable_i = 1'b0;
        iteration_count = 0;
        test_complete = 1'b0;
        current_state = 384'h0;

        for (i = 0; i < 12; i = i + 1)
            state_words[i] = 32'h0;

        expected_final = {
            32'heb092faf, 32'h1597394f, 32'hfc4c41e0, 32'hf1826ca5,
            32'hfe2eff69, 32'hfe12521b, 32'h14649e0a, 32'hea36eba3,
            32'h2a7ae5cf, 32'h29c62ee7, 32'h42d5d8ce, 32'hfe04fab0
        };
                
        // Release reset
        @(posedge clk_i);
        rst_i = 1'b0;
        #1;
                
        @(posedge clk_i);
        init_reg = 1'b1;
        #1;
        init_reg = 1'b0;
        
        // Wait one cycle after init_reg to ensure state is cleared
        @(posedge clk_i);
        #1;
        
        // Note: For first permutation, we start with all zeros
        // No word loading needed for first permutation (state is already zero)
        // Start the first permutation
        @(posedge clk_i);
        #1;
        start_i = 1'b1;
        @(posedge clk_i);
        #1;
        start_i = 1'b0;
    end
    
    // Task to read state word-by-word
    task read_state;
        integer idx;
        begin
            for (idx = 0; idx < 12; idx = idx + 1) begin
                // Set word_index_in first
                word_index_in = idx;
                @(posedge clk_i);
                #2;
                state_words[idx] = word_out;
            end
        end
    endtask
    
    // Task to write state word-by-word
    task write_state;
        integer idx;
        begin
            for (idx = 0; idx < 12; idx = idx + 1) begin
                @(posedge clk_i);
                word_index_in = idx;
                word_in = state_words[idx];
                word_enable_in = 1'b1;
                #2;
                word_enable_in = 1'b0;
            end
        end
    endtask
    
    // State machine for reading state word-by-word
    reg [3:0] read_word_idx;
    reg reading_state;
    reg state_read_complete;
    reg just_finished_reading;  // Flag to mark we just finished reading
    reg first_read_cycle;  // Flag to track first cycle of reading
    
    // State machine for writing state word-by-word
    reg [3:0] write_word_idx;
    reg writing_state;
    reg state_write_complete;
    
    // State machine for processing read state and preparing next iteration
    reg [1:0] process_state;  // 0=idle, 1=init_reg_assert, 2=init_reg_deassert, 3=wait_after_init
    reg process_delay;
    
    // Initialize state machines
    initial begin
        reading_state = 1'b0;
        read_word_idx = 4'h0;
        state_read_complete = 1'b0;
        just_finished_reading = 1'b0;
        first_read_cycle = 1'b0;
        writing_state = 1'b0;  // Don't start writing until explicitly enabled
        write_word_idx = 4'h0;
        state_write_complete = 1'b0;
        process_state = 2'd0;
        process_delay = 1'b0;
    end

    // Combined state machine for word_index_in control (writing and reading are mutually exclusive)
    always @(posedge clk_i) begin
        if (writing_state) begin
            // Writing: set word_index_in to current write index
            word_index_in <= write_word_idx;
            word_in <= state_words[write_word_idx];
            word_enable_in <= 1'b1;
            
            if (write_word_idx == 4'd11) begin
                // After writing word 11, deassert enable on next cycle
                writing_state <= 1'b0;
                write_word_idx <= 4'h0;
                state_write_complete <= 1'b1;
            end else begin
                // Move to next word
                write_word_idx <= write_word_idx + 1;
                state_write_complete <= 1'b0;
            end
        end else if (just_finished_reading) begin
            // One cycle after finishing reading - mark complete now
            state_read_complete <= 1'b1;
            just_finished_reading <= 1'b0;
            word_enable_in <= 1'b0;
            word_index_in <= 4'h0;
        end else if (reading_state) begin
            // Reading: word_out is combinational, reflects current word_index_in
            word_enable_in <= 1'b0;
            
            if (first_read_cycle) begin
                // First cycle: word_index_in was just set to 0, wait one cycle before reading
                // word_out will be valid next cycle
                first_read_cycle <= 1'b0;
                word_index_in <= 4'h0;  // Keep at 0 for first read
                // Don't read yet, just prepare for next cycle
            end else begin
                // Read current word from word_out
                // word_out reflects word_index_in set in previous cycle
                state_words[read_word_idx] <= word_out;
                
                if (read_word_idx == 4'd11) begin
                    // Finished reading all 12 words (just read word 11)
                    // Wait one more cycle before marking complete to ensure all assignments settle
                    reading_state <= 1'b0;
                    read_word_idx <= 4'h0;
                    word_index_in <= 4'h0;
                    just_finished_reading <= 1'b1;  // Mark that we just finished
                    first_read_cycle <= 1'b0;
                end else begin
                    // Move to next word - set word_index_in for next cycle's read
                    read_word_idx <= read_word_idx + 1;
                    word_index_in <= read_word_idx + 1;
                    just_finished_reading <= 1'b0;
                end
            end
        end else begin
            // Idle: clear signals
            word_enable_in <= 1'b0;
            word_index_in <= 4'h0;
        end
    end
    
    // Monitor state_valid_o and start reading
    always @(posedge clk_i) begin
        if (state_valid_o && !test_complete && !reading_state && !state_read_complete && !writing_state && process_state == 2'd0 && !just_finished_reading) begin
            // Start reading state word-by-word
            // Set word_index_in to 0 first, then start reading on next cycle
            reading_state <= 1'b1;
            read_word_idx <= 4'h0;
            state_read_complete <= 1'b0;
            just_finished_reading <= 1'b0;
            first_read_cycle <= 1'b1;  // Mark first cycle
            word_index_in <= 4'h0;  // Set index for first word
        end
    end
    
    // Process state after reading is complete
    always @(posedge clk_i) begin
        if (state_read_complete && !test_complete && process_state == 2'd0) begin
            // Pack words into current_state (word_index_in=0 is LSB, word_index_in=11 is MSB)

            // Debug: display individual words to verify reading
            // $display("State words: [11]=%h [10]=%h [9]=%h [8]=%h [7]=%h [6]=%h [5]=%h [4]=%h [3]=%h [2]=%h [1]=%h [0]=%h",
            //     state_words[11], state_words[10], state_words[9], state_words[8],
            //     state_words[7], state_words[6], state_words[5], state_words[4],
            //     state_words[3], state_words[2], state_words[1], state_words[0]);

            current_state = {
                state_words[11], state_words[10], state_words[9], state_words[8],
                state_words[7], state_words[6], state_words[5], state_words[4],
                state_words[3], state_words[2], state_words[1], state_words[0]
            };

            // $display("Current state: %h", current_state);
            
            // Reset reading complete flag
            state_read_complete <= 1'b0;
            
            // Increment iteration counter
            iteration_count = iteration_count + 1;
            
            if (current_state == expected_final) begin
                    $display("*** Same final state test PASSED ***");
            end
            
            // Check if we've reached 384 iterations (like original test)
            if (iteration_count >= 384) begin
                test_complete = 1'b1;
                process_state <= 2'd0;
                $display("Simulation completed at time %0t", $time);
                $display("Current state: %h", current_state);
            end else begin
                // Move to init_reg state
                process_state <= 2'd1;  // Start init_reg sequence
            end
        end else if (process_state == 2'd1) begin
            // Assert init_reg
            init_reg <= 1'b1;
            process_state <= 2'd2;
        end else if (process_state == 2'd2) begin
            // Deassert init_reg
            init_reg <= 1'b0;
            process_state <= 2'd3;
        end else if (process_state == 2'd3) begin
            // Wait one cycle after init_reg, then start writing
            process_state <= 2'd0;
            // Start writing state word-by-word for next permutation
            writing_state <= 1'b1;
            write_word_idx <= 4'h0;
            state_write_complete <= 1'b0;
        end
    end
    
    // Finish simulation when test is complete
    always @(posedge clk_i) begin
        if (test_complete && !process_delay) begin
            process_delay <= 1'b1;
        end else if (process_delay) begin
            $display("Simulation completed at time %0t", $time);
            $finish;
        end
    end
    
    // Start next permutation after writing is complete
    always @(posedge clk_i) begin
        if (state_write_complete && !test_complete) begin
            state_write_complete <= 1'b0;
            
            // Start next permutation on next cycle
            start_i <= 1'b1;
        end else if (start_i) begin
            // Deassert start_i after one cycle
            start_i <= 1'b0;
        end
    end
    
    
endmodule

